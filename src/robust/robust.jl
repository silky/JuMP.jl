export RobustModel, Uncertain, UAffExpr, FullAffExpr
export affToStr, affToStr
export Affine
export @defUnc

type RobustModel
  obj
  objSense::Symbol
  
  certainconstr
  uncertainconstr
  uncertaintyset
  
  # Column data
  numCols::Int
  colNames::Vector{String}
  colLower::Vector{Float64}
  colUpper::Vector{Float64}
  colCat::Vector{Int}

  # Uncertainty data
  numUncs::Int
  uncNames::Vector{String}
  uncLower::Vector{Float64}
  uncUpper::Vector{Float64}
  
  # Solution data
  objVal
  colVal::Vector{Float64}
  redCosts::Vector{Float64}
  #linconstrDuals::Vector{Float64}
  # internal solver model object
  internalModel
  # Solver+option object from MathProgBase
  solver::AbstractMathProgSolver
end

# Default constructor
function RobustModel(;solver=nothing)
  if solver == nothing
    RobustModel(AffExpr(),:Min,
                LinearConstraint[],Any[],Any[],
                0,String[],Float64[],Float64[],Int[],
                0,String[],Float64[],Float64[],
                0,Float64[],Float64[],nothing,MathProgBase.MissingSolver("",Symbol[]))
  else
    if !isa(solver,AbstractMathProgSolver)
      error("solver argument ($solver) must be an AbstractMathProgSolver")
    end
    # user-provided solver must support problem class
    RobustModel(AffExpr(),:Min,
                LinearConstraint[],Any[],Any[],
                0,String[],Float64[],Float64[],Int[],
                0,String[],Float64[],Float64[],
                0,Float64[],Float64[],nothing,solver)
  end

end

function setObjective(m::RobustModel, sense::Symbol, a::AffExpr)
  m.obj = a
  m.objSense = sense
end

# Pretty print
function print(io::IO, m::RobustModel)
  println(io, string(m.objSense," ",affToStr(m.obj)))
  println(io, "Subject to: ")
  println(io, "Constraints with no uncertainties:")
  for c in m.certainconstr
    println(io, conToStr(c))
  end
  println(io, "Constraints with uncertainties:")
  for c in m.uncertainconstr
    println(io, conToStr(c))
  end
  println(io, "Uncertainty set:")
  for c in m.uncertaintyset
    println(io, conToStr(c))
  end
  for i in 1:m.numUncs
    print(io, m.uncLower[i])
    print(io, " <= ")
    print(io, (m.uncNames[i] == "" ? string("_unc",i) : m.uncNames[i]))
    print(io, " <= ")
    println(io, m.uncUpper[i])
  end

  println(io, "Variable bounds:")
  for i in 1:m.numCols
    print(io, m.colLower[i])
    print(io, " <= ")
    print(io, (m.colNames[i] == "" ? string("_col",i) : m.colNames[i]))
    print(io, " <= ")
    println(io, m.colUpper[i])
  end
end

getNumVars(m::RobustModel) = m.numCols

# Variable class
function Variable(m::RobustModel,lower::Number,upper::Number,cat::Int,name::String)
  m.numCols += 1
  push!(m.colNames, name)
  push!(m.colLower, convert(Float64,lower))
  push!(m.colUpper, convert(Float64,upper))
  push!(m.colCat, cat)
  return Variable(m, m.numCols)
end
Variable(m::RobustModel,lower::Number,upper::Number,cat::Int) = Variable(m,lower,upper,cat,"")
getName(m::RobustModel, col) = (m.colNames[col] == "" ? string("_col",col) : m.colNames[col])

function Affine(rm::RobustModel, lower, upper, name, uncertains)
  expr = AffExpr()
  # Non affine part
  g = Variable(rm, -Inf, +Inf, 0, string(name,"_g"))
  expr += g
  # Affine part
  for u in uncertains
    f = Variable(rm, -Inf, +Inf, 0, string(name,"_",getName(u)))
    expr += u*f
  end
  # Bounds
  if lower != -Inf
    addConstraint(rm, expr >= lower)
  end
  if upper != +Inf
    addConstraint(rm, expr <= upper)
  end
  return expr
end

function printAffine(expr)
  println(affToStr(expr))
  rm = expr.vars[1].m
  for i in 2:length(expr.vars)
    print(getValue(expr.vars[i]), " ", getName(expr.coeffs[i].uncs[1]), " + ")
  end
  println(getValue(expr.vars[1]))
end
export printAffine

###############################################################################
# Uncertain class
# Doesn't actually do much, just a pointer back to the model
type Uncertain
  m::RobustModel
  unc::Int
end

function Uncertain(m::RobustModel,lower::Number,upper::Number,name::String)
  m.numUncs += 1
  push!(m.uncNames, name)
  push!(m.uncLower, convert(Float64,lower))
  push!(m.uncUpper, convert(Float64,upper))
  return Uncertain(m, m.numUncs)
end

Uncertain(m::RobustModel,lower::Number,upper::Number) =
  Uncertain(m,lower,upper,"")

# Name setter/getters
setName(u::Uncertain,n::String) = (u.m.uncNames[v.col] = n)
getName(u::Uncertain) = (u.m.uncNames[u.unc] == "" ? string("_unc",u.unc) : u.m.uncNames[u.unc])
getNameU(m::RobustModel, unc) = (m.uncNames[unc] == "" ? string("_unc",unc) : m.uncNames[unc])
print(io::IO, u::Uncertain) = print(io, getName(u))
show(io::IO, u::Uncertain) = print(io, getName(u))

###############################################################################
# Uncertain Affine Expression class
# Holds a vector of tuples (Unc, Coeff)
type UAffExpr
  uncs::Array{Uncertain,1}
  coeffs::Array{Float64,1}
  constant::Float64
end

UAffExpr() = UAffExpr(Uncertain[],Float64[],0.)
UAffExpr(c::Float64) = UAffExpr(Uncertain[],Float64[],c)
UAffExpr(u::Uncertain, c::Float64) = UAffExpr([u],[c],0.)
UAffExpr(coeffs::Array{Float64,1}) = [UAffExpr(c) for c in coeffs]
zero(::Type{UAffExpr}) = UAffExpr()  # For zeros(UAffExpr, dims...)

print(io::IO, a::UAffExpr) = print(io, affToStr(a))
show(io::IO, a::UAffExpr) = print(io, affToStr(a))

function affToStr(a::UAffExpr, showConstant=true)
  if length(a.uncs) == 0
    return string(a.constant)
  end

  # Get reference to model
  m = a.uncs[1].m

  # Collect like terms
  indvec = IndexedVector(Float64,m.numUncs)
  for ind in 1:length(a.uncs)
    addelt(indvec, a.uncs[ind].unc, a.coeffs[ind])
  end

  # Stringify the terms
  termStrings = Array(ASCIIString, length(a.uncs))
  numTerms = 0
  for i in 1:indvec.nnz
    idx = indvec.nzidx[i]
    numTerms += 1
    termStrings[numTerms] = "$(indvec.elts[idx]) $(getNameU(m,idx))"
  end

  # And then connect them up with +s
  ret = join(termStrings[1:numTerms], " + ")
  
  if abs(a.constant) >= 0.000001 && showConstant
    ret = string(ret," + ",a.constant)
  end
  return ret
end

###############################################################################
# Full Affine Expression class
# TODO(idunning): Better name. In my other robust modelling tools I called it
# something like this, but the catch then was that there we only two types of
# affexpr - the one with UAffExpr coefficients = Full, and the UAffExpr itself
# Holds a vector of tuples (Unc, Coeff)
typealias FullAffExpr GenericAffExpr{UAffExpr,Variable}

FullAffExpr() = FullAffExpr(Variable[],UAffExpr[],UAffExpr())

# Pretty cool that this is almost the same as normal affExpr
function affToStr(a::FullAffExpr, showConstant=true)
  if length(a.vars) == 0
    return string(a.constant)
  end

  # Get reference to model
  m = a.vars[1].m

  # Collect like terms
  #indvec = IndexedVector(UAffExpr, m.numCols)
  #for ind in 1:length(a.vars)
  #  addelt(indvec, a.vars[ind].col, a.coeffs[ind])
  #end

  # Stringify the terms
  termStrings = Array(ASCIIString, length(a.vars))
  numTerms = 0
  for i in 1:length(a.vars) #indvec.nnz
    #idx = indvec.nzidx[i]
    numTerms += 1
    termStrings[numTerms] = "($(affToStr(a.coeffs[i]))) $(getName(a.vars[i]))"
  end

  # And then connect them up with +s
  ret = join(termStrings[1:numTerms], " + ")
  
  # TODO(idunning): Think more carefully about this
  #if abs(a.constant) >= 0.000001 && showConstant
  if showConstant
    ret = string(ret," + ",affToStr(a.constant))
  end
  return ret
end

##########################################################################
# UncSetConstraint class
# A constraint just involving uncertainties
type UncSetConstraint <: JuMPConstraint
  terms::UAffExpr
  lb::Float64
  ub::Float64
end

UncSetConstraint(terms::UAffExpr,lb::Number,ub::Number) =
  UncSetConstraint(terms,float(lb),float(ub))

function addConstraint(m::RobustModel, c::UncSetConstraint)
  push!(m.uncertaintyset,c)
  #TODO: Hack
  #return ConstraintRef{UncSetConstraint}(m,length(m.uncertaintyset))
end

print(io::IO, c::UncSetConstraint) = print(io, conToStr(c))
show(io::IO, c::UncSetConstraint) = print(io, conToStr(c))

function sense(c::UncSetConstraint)
  if c.lb != -Inf
    if c.ub != Inf
      if c.ub == c.lb
        return :(==)
      else
        return :range
      end
    else
        return :>=
    end
  else
    @assert c.ub != Inf
    return :<=
  end
end

function rhs(c::UncSetConstraint)
  s = sense(c)
  @assert s != :range
  if s == :<=
    return c.ub
  else
    return c.lb
  end
end

function conToStr(c::UncSetConstraint)
  s = sense(c)
  if s == :range
    return string(c.lb," <= ",affToStr(c.terms,false)," <= ",c.ub)
  else
    return string(affToStr(c.terms,false)," ",s," ",rhs(c))
  end
end

##########################################################################
# UncConstraint class
# A mix of variables and uncertains
type UncConstraint <: JuMPConstraint
  terms::FullAffExpr
  lb::Float64
  ub::Float64
  wrangler #::AbstractWrangler
end

UncConstraint(terms::FullAffExpr,lb::Number,ub::Number) =
  UncConstraint(terms,float(lb),float(ub),SimpleLPWrangler())

function addConstraint(m::RobustModel, c::UncConstraint)
  push!(m.uncertainconstr,c)
  # TODO: HACK
  #return ConstraintRef{UncConstraint}(Model(:Max),length(m.uncertainconstr))
end

print(io::IO, c::UncConstraint) = print(io, conToStr(c))
show(io::IO, c::UncConstraint) = print(io, conToStr(c))

function sense(c::UncConstraint)
  if c.lb != -Inf
    if c.ub != Inf
      if c.ub == c.lb
        return :(==)
      else
        return :range
      end
    else
        return :>=
    end
  else
    @assert c.ub != Inf
    return :<=
  end
end

function rhs(c::UncConstraint)
  s = sense(c)
  @assert s != :range
  if s == :<=
    return c.ub
  else
    return c.lb
  end
end

function conToStr(c::UncConstraint)
  s = sense(c)
  if s == :range
    return string(c.lb," <= ",affToStr(c.terms)," <= ",c.ub)
  else
    return string(affToStr(c.terms)," ",s," ",rhs(c))
  end
end

##########################################################################
# LinearConstraint class
# An affine expression with lower bound (possibly -Inf) and upper bound (possibly Inf).
function addConstraint(m::RobustModel, c::LinearConstraint)
  push!(m.certainconstr,c)
  # TODO this is broken because ConstraintRef expects Model
  return ConstraintRef{LinearConstraint}(Model(),length(m.certainconstr))
end

include("robustops.jl")
include("robustsolve.jl")
include("wrangler.jl")
include("robustmacro.jl")
