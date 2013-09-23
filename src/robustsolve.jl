abstract RobustOracle

###############################################################################
# LPRobustOracle
# A generic cutting LP that is automatically generated.

type LPRobustOracle <: RobustOracle
  orig_model::RobustModel
  con::UncConstraint
  cutting::Model
  cutvars

  # Mapping from master to cut
  var_map
  constant_coeffs
end

function LPRobustOracle(m::RobustModel, con::UncConstraint)
  # Create a Model for this cutting LP
  cutting = Model(:Min)
  # The objective sense is based on the sense of the constraint
  if sense(con) == :<=
    cutting.objSense = :Max
  end
  # Copy uncertainty set from original problem
  cutting.numCols = m.numUncs
  cutting.colNames = m.uncNames
  cutting.colLower = m.uncLower
  cutting.colUpper = m.uncUpper
  cutting.colCat = zeros(m.numUncs)
  cutvars = [Variable(cutting, i) for i = 1:m.numUncs]

  # Build up map from master solution to cutting objective
  terms = con.terms
  num_vars = length(terms.coeffs)
  var_map = Dict{Int,Any}()
  for i = 1:num_vars
    col = terms.vars[i].col
    var_map[col] = Any[]
    num_uncs = length(terms.coeffs[i].uncs)
    for j = 1:num_uncs
      unc = terms.coeffs[i].uncs[j].unc
      coeff = terms.coeffs[i].coeffs[j]
      push!(var_map[col], (unc,coeff))
    end
  end
  # Including the constant term
  constant_coeffs = Any[]
    num_uncs = length(terms.constant.uncs)
    for j = 1:num_uncs
      unc = terms.constant.uncs[j].unc
      coeff = terms.constant.coeffs[j]
      push!(constant_coeffs, (unc,coeff))
    end


  return LPRobustOracle(m, con, cutting, cutvars, var_map, constant_coeffs)
end

function generateCut(oracle::LPRobustOracle, master::Model)
  master_sol = master.colVal

  # Shove the master solution into the objective
  num_uncs = oracle.cutting.numCols
  unc_coeffs = zeros(num_uncs)
  for key in keys(oracle.var_map)
    for pair in oracle.var_map[key]
      unc_coeffs[pair[1]] += pair[2]*master_sol[key]
    end
  end
    for pair in oracle.constant_coeffs
      unc_coeffs[pair[1]] += pair[2]
    end
  @setObjective(oracle.cutting, sum{unc_coeffs[i]*oracle.cutvars[i], i = 1:num_uncs})

  # Solve it
  println("CUT FOR CON: $(conToStr(oracle.con))")
  println(oracle.cutting)
  println("ENDCUT")

  solve(oracle.cutting)
  println("Cut solution:")
  println(oracle.cutting.colVal)

  # Now add that back in
  num_vars = length(oracle.con.terms.vars)
  aff = AffExpr(oracle.con.terms.vars,
                [oracle.con.terms.coeffs[i].constant for i in 1:num_vars],
                oracle.con.terms.constant.constant)
  for var_ind = 1:num_vars
    coeff::UAffExpr = oracle.con.terms.coeffs[var_ind]
    num_uncs = length(coeff.uncs)
    for unc_ind = 1:num_uncs
      coeff_unc = coeff.uncs[unc_ind]
      coeff_coeff = coeff.coeffs[unc_ind]
      aff.coeffs[var_ind] += oracle.cutting.colVal[coeff_unc.unc]*coeff_coeff[unc_ind]
    end
    # Add the non-uncertain part
  end
  # TODO don't forget the constant
  push!(master.linconstr, LinearConstraint(aff, oracle.con.lb, oracle.con.ub))

end

###############################################################################


function quadToStr(a::AffExpr)
  # Hack...
  return affToStr(a)
end


function solve(m::RobustModel)

  # Initially use cutting planes
  # Make a master and sub problem

  # MASTER PROBLEM
  master = Model(m.objSense)
  master.obj = QuadExpr(Variable[],Variable[],Float64[],m.obj)
  master.linconstr = m.certainconstr
  master.numCols = m.numCols
  master.colNames = m.colNames
  master.colLower = m.colLower
  master.colUpper = m.colUpper
  master.colCat = m.colCat
  mastervars = [Variable(master, i) for i = 1:m.numCols]

  println("INITIAL MASTER")
  println(master)
  println("END MASTER")

  # CUTTING PROBLEMS
  oracles = [LPRobustOracle(m,m.uncertainconstr[i]) for i = 1:length(m.uncertainconstr)]

  # Begin da loop
  #while true
  for iter = 1:2
    # Solve master
    master_status = solve(master)
    println("Solved master")
    println("INITIAL MASTER")
    println(master)
    println("END MASTER")
    println("Master solution:")
    println(master.colVal)

    # Generate cuts
    for i = 1:length(m.uncertainconstr)
      generateCut(oracles[i], master)
    end
  end
end
