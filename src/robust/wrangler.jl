#############################################################################
# JuMP
# An algebraic modelling langauge for Julia
# See http://github.com/JuliaOpt/JuMP.jl
#############################################################################
# Wranglers
# Wranglers are "robustifying operators", that can (optionally) take a
# constraint and either provide
# a) a reformulation
# b) a seperation oracle
# as required.
#############################################################################

#############################################################################
# AbstractWrangler
# All wranglers implement the interface defined by AbstractWrangler
abstract AbstractWrangler

# querySupport
# Called by the main solver algorithm to determine what is possible with this
# wrangler. For now, the wrangler makes this decision without knowing the
# constraint it is dealing with but that could change. Returns a symbol, one
# of :Cut, :Reform, or :Both. If :Both, the solver will use the preferred
querySupport(w::AbstractWrangler) = error("Not implemented")

# setup
# Gives wrangler time to do any setup it needs to do based on selected mode of
# operation and the full model.
setup!(w::AbstractWrangler, sel_mode::Symbol, constraint, rm::RobustModel) = error("Not implemented")

# generateCut
# Called in the main loop every iteration, rm is the original problem and m is
# the actual current model being solved (that will have the current solution)
# Returns a tuple true if new constraint added, false otherwise.
generateCut(w::AbstractWrangler, m::Model) = error("Not implemented")

# generateReform
# Called before the main loop, adds anything it wants to the model
generateReform(w::AbstractWrangler, rm::RobustModel, m::Model) = error("Not implemented")


#############################################################################
# SimpleLPWrangler
# The basic, familiar polyhedral uncertainty set wrangler.
type SimpleLPWrangler
  cutting::Model
  cutvars::Vector{Variable}

  # Mapping from master to cut
  var_map
  constant_coeffs

  # The original constraint
  con
end
SimpleLPWrangler() = SimpleLPWrangler(Model(), Variable[], nothing, nothing, nothing)

querySupport(w::SimpleLPWrangler) = :Cut

function setup!(w::SimpleLPWrangler, sel_mode::Symbol, con, rm::RobustModel)
  # Do no work if reformulation was selected
  if sel_mode == :Reform
    return
  end

  # Store reference to the original constraint
  w.con = con

  # Create an LP that we'll use to solve the cut problem
  w.cutting.objSense = sense(con) == :<= ? :Max : :Min

  # Copy the uncertainty set from the original problem
  w.cutting.numCols = rm.numUncs
  w.cutting.colNames = rm.uncNames
  w.cutting.colLower = rm.uncLower
  w.cutting.colUpper = rm.uncUpper
  w.cutting.colCat = zeros(rm.numUncs)
  w.cutvars = [Variable(w.cutting, i) for i = 1:rm.numUncs]
  for c in rm.uncertaintyset
    # Con is in terms of "uncs" in rm
    # Coefficients are the same, but variables are not
    newcon = LinearConstraint(AffExpr(), c.lb, c.ub)
    newcon.terms.coeffs = c.terms.coeffs
    newcon.terms.vars = [w.cutvars[u.unc] for u in c.terms.uncs]
    push!(w.cutting.linconstr, newcon)
  end

  # Build up a map from the master solution to the cut objective
  # w.var_map: key = column numbers, value = [(unc_ind, coeff)]
  # w.constant_coeffs = [(unc_ind, coeff)]
  terms = con.terms
  num_vars = length(terms.coeffs)  # Number of variables in constraint
  w.var_map = Dict{Int,Any}()
  for i = 1:num_vars  # For every (uncertain_expr, variable) pair
    col = terms.vars[i].col  # Extract column number == key
    w.var_map[col] = Any[]  # Initialize array of tuples to empty
    num_uncs = length(terms.coeffs[i].uncs)  # Number of uncertains in coeff expr
    for j = 1:num_uncs  # For every uncertainty in front of this variable
      unc = terms.coeffs[i].uncs[j].unc  # The unc_ind of this uncertain
      coeff = terms.coeffs[i].coeffs[j]  # The coeff on that uncertain
      push!(w.var_map[col], (unc,coeff))
    end
  end
  # Including the constant term
  w.constant_coeffs = Any[]
    num_uncs = length(terms.constant.uncs)
    for j = 1:num_uncs
      unc = terms.constant.uncs[j].unc
      coeff = terms.constant.coeffs[j]
      push!(w.constant_coeffs, (unc,coeff))
    end
end


function generateCut(w::SimpleLPWrangler, m::Model)
  master_sol = m.colVal

  # Shove the master solution into the objective using our map
  # Accumulate the coefficients for each uncertaint
  num_uncs = w.cutting.numCols
  unc_coeffs = zeros(num_uncs)
  for key in keys(w.var_map)  # For every var in original con
    for pair in w.var_map[key]  # For every uncertain applied to that var
      unc_coeffs[pair[1]] += pair[2]*master_sol[key]
    end
  end
    for pair in w.constant_coeffs
      unc_coeffs[pair[1]] += pair[2]
    end
  @setObjective(w.cutting, w.cutting.objSense, sum{unc_coeffs[i]*w.cutvars[i], i = 1:num_uncs})

  # Solve it
  #println("CUT FOR CON: $(conToStr(oracle.con))")
  #println(oracle.cutting)
  #println("ENDCUT")

  solve(w.cutting)
  #println("Cut solution:")
  #println(oracle.cutting.colVal)

  # Now add that solution back in
  # TODO: Build map for this too
  num_vars = length(w.con.terms.vars)
  aff = AffExpr( w.con.terms.vars,
                float([w.con.terms.coeffs[i].constant for i in 1:num_vars]),
                 w.con.terms.constant.constant)
  # Variable part
  for var_ind = 1:num_vars
    coeff::UAffExpr = w.con.terms.coeffs[var_ind]
    num_uncs = length(coeff.uncs)
    for unc_ind = 1:num_uncs
      coeff_unc = coeff.uncs[unc_ind]
      coeff_coeff = coeff.coeffs[unc_ind]
      aff.coeffs[var_ind] += w.cutting.colVal[coeff_unc.unc] * coeff_coeff[unc_ind]
    end
  end
  # Non variable part
    coeff = w.con.terms.constant
    num_uncs = length(coeff.uncs)
    for unc_ind = 1:num_uncs
      coeff_unc = coeff.uncs[unc_ind]
      coeff_coeff = coeff.coeffs[unc_ind]
      aff.constant += w.cutting.colVal[coeff_unc.unc] * coeff_coeff[unc_ind]
    end

  if w.con.lb == -Inf
    # LEQ constriant
    @addConstraint(m, aff <= w.con.ub)
  elseif w.con.ub == +Inf
    # GEQ constraint
    @addConstraint(m, aff >= w.con.lb)
  else
    # EQ or range - not allowed
    error("Cannot robustify range constraints or equality constraints")
  end

end

