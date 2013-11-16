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
  return ConstraintRef{LinearConstraint}(Model(:Max),length(m.certainconstr))
end

###########################################################
# Overloads
# 1. Number
# 2. Variable
# 3. AffExpr
# 4. QuadExpr <- DISREGARD
# 5. Constraint (for comparison ops)
# ---
# 6. Uncertain
# 7. UAffExpr
# 8. FullAffExpr

# Number
# Number--Uncertain
(+)(lhs::Number, rhs::Uncertain) = UAffExpr([rhs],[+1.],convert(Float64,lhs))
(-)(lhs::Number, rhs::Uncertain) = UAffExpr([rhs],[-1.],convert(Float64,lhs))
(*)(lhs::Number, rhs::Uncertain) = UAffExpr([rhs],[convert(Float64,lhs)], 0.)
(/)(lhs::Number, rhs::Uncertain) = error("Cannot divide by an uncertain")
# Number--UAffExpr
(+)(lhs::Number, rhs::UAffExpr) = UAffExpr(copy(rhs.uncs),copy(rhs.coeffs),lhs+rhs.constant)
(-)(lhs::Number, rhs::UAffExpr) = UAffExpr(copy(rhs.uncs),    -rhs.coeffs ,lhs-rhs.constant)
(*)(lhs::Number, rhs::UAffExpr) = UAffExpr(copy(rhs.uncs), lhs*rhs.coeffs ,lhs*rhs.constant)
(/)(lhs::Number, rhs::UAffExpr) = error("Cannot divide number by an uncertain expression")
# Number--FullAffExpr
(+)(lhs::Number, rhs::FullAffExpr) = FullAffExpr(copy(rhs.vars),copy(rhs.coeffs),lhs+rhs.constant)
(-)(lhs::Number, rhs::FullAffExpr) = FullAffExpr(copy(rhs.vars),[0.0-rhs.coeffs[i] for i=1:length(rhs.coeffs)],lhs-rhs.constant)
(*)(lhs::Number, rhs::FullAffExpr) = FullAffExpr(copy(rhs.vars),[lhs*rhs.coeffs[i] for i=1:length(rhs.coeffs)] ,lhs*rhs.constant)
(/)(lhs::Number, rhs::FullAffExpr) = error("Cannot divide number by an expression")

# Variable
# Variable--Uncertain
(+)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(1.)],UAffExpr(rhs,+1.))
(-)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(1.)],UAffExpr(rhs,-1.))
(*)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(rhs,1.0)],UAffExpr())
(/)(lhs::Variable, rhs::Uncertain) = error("Cannot divide a variable by an uncertain")
# Variable--UAffExpr
(+)(lhs::Variable, rhs::UAffExpr) = FullAffExpr([lhs],[UAffExpr(1.)],    rhs)
(-)(lhs::Variable, rhs::UAffExpr) = FullAffExpr([lhs],[UAffExpr(1.)],0.0-rhs)
(*)(lhs::Variable, rhs::UAffExpr) = FullAffExpr([lhs],[rhs],UAffExpr())
(/)(lhs::Variable, rhs::UAffExpr) = error("Cannot divide a variable by an expression")
# Variable--FullAffExpr
(+)(lhs::Variable, rhs::FullAffExpr) = FullAffExpr(vcat(rhs.vars,lhs),vcat(rhs.coeffs,UAffExpr(1.)), rhs.constant)
(-)(lhs::Variable, rhs::FullAffExpr) = FullAffExpr(vcat(rhs.vars,lhs),vcat([0.0-rhs.coeffs[i] for i=1:length(rhs.coeffs)],UAffExpr(1.)),0.0-rhs.constant)
(*)(lhs::Variable, rhs::FullAffExpr) = error("Cannot multiply variable and expression")
(/)(lhs::Variable, rhs::FullAffExpr) = error("Cannot divide variable by expression")

# AffExpr
# AffExpr--Uncertain
(+)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars,UAffExpr(lhs.coeffs), UAffExpr([rhs],[+1.],lhs.constant))
(-)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars,UAffExpr(lhs.coeffs), UAffExpr([rhs],[-1.],lhs.constant))
(*)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars,[UAffExpr(rhs,lhs.coeffs[i]) for i=1:length(lhs.vars)], UAffExpr(rhs,lhs.constant))
(/)(lhs::AffExpr, rhs::Uncertain) = error("Cannot divide affine expression by an uncertain")
# AffExpr-UAffExpr
(+)(lhs::AffExpr, rhs::UAffExpr) = FullAffExpr(copy(lhs.vars),UAffExpr(lhs.coeffs),lhs.constant+rhs)
(-)(lhs::AffExpr, rhs::UAffExpr) = FullAffExpr(copy(lhs.vars),UAffExpr(lhs.coeffs),lhs.constant-rhs)
(*)(lhs::AffExpr, rhs::UAffExpr) = FullAffExpr(copy(lhs.vars),[lhs.coeffs[i]*rhs for i=1:length(lhs.vars)],lhs.constant*rhs)
(/)(lhs::AffExpr, rhs::UAffExpr) = error("Cannot divide affine expression by an uncertain expression")
# AffExpr-FullAffExpr
(+)(lhs::AffExpr, rhs::FullAffExpr) = FullAffExpr(
  vcat(lhs.vars, rhs.vars),
  vcat(UAffExpr(lhs.coeffs), rhs.coeffs),
  lhs.constant + rhs.constant)
(-)(lhs::AffExpr, rhs::FullAffExpr) = FullAffExpr(
  vcat(lhs.vars, rhs.vars),
  vcat(UAffExpr(lhs.coeffs), [0.0-rhs.coeffs[i] for i=1:length(rhs.coeffs)]),
  lhs.constant - rhs.constant)
(*)(lhs::AffExpr, rhs::FullAffExpr) = error("Cannot multiply expressions")
(/)(lhs::AffExpr, rhs::FullAffExpr) = error("Cannot divide expressions")

# Constraints
# UAffExpr
function (<=)(lhs::UAffExpr, rhs::Number)
  rhs -= lhs.constant
  lhs.constant = 0
  return UncSetConstraint(lhs,-Inf,rhs)
end
function (==)(lhs::UAffExpr, rhs::Number)
  rhs -= lhs.constant
  lhs.constant = 0
  return UncSetConstraint(lhs,rhs,rhs)
end
function (>=)(lhs::UAffExpr, rhs::Number)
  rhs -= lhs.constant
  lhs.constant = 0
  return UncSetConstraint(lhs,rhs,Inf)
end
# FullAffExpr
function (<=)(lhs::FullAffExpr, rhs::Number)
  rhs -= lhs.constant.constant
  lhs.constant.constant = 0
  return UncConstraint(lhs,-Inf,rhs)
end
function (==)(lhs::FullAffExpr, rhs::Number)
  rhs -= lhs.constant.constant
  lhs.constant.constant = 0
  return UncConstraint(lhs,rhs,rhs)
end
function (>=)(lhs::FullAffExpr, rhs::Number)
  rhs -= lhs.constant.constant
  lhs.constant.constant = 0
  return UncConstraint(lhs,rhs,Inf)
end

# Uncertain
(-)(lhs::Uncertain) = UAffExpr([lhs],[-1.],0.)
# Uncertain--Number
(+)(lhs::Uncertain, rhs::Number) = (+)(   +rhs, lhs)
(-)(lhs::Uncertain, rhs::Number) = (+)(   -rhs, lhs)
(*)(lhs::Uncertain, rhs::Number) = (*)(    rhs, lhs)
(/)(lhs::Uncertain, rhs::Number) = (*)(1.0/rhs, lhs)
# Uncertain--Variable
(+)(lhs::Uncertain, rhs::Variable) = (+)(rhs, lhs)
(-)(lhs::Uncertain, rhs::Variable) = FullAffExpr([rhs],[UAffExpr(-1.)],UAffExpr(lhs,+1.))
(*)(lhs::Uncertain, rhs::Variable) = (*)(rhs, lhs)
(/)(lhs::Uncertain, rhs::Variable) = error("Cannot divide uncertain by variable")
# Uncertain--AffExpr
(+)(lhs::Uncertain, rhs::AffExpr) = (+)(rhs, lhs)
(-)(lhs::Uncertain, rhs::AffExpr) = FullAffExpr(rhs.vars, UAffExpr(-rhs.coeffs), UAffExpr([lhs],[1.],-rhs.constant))
(*)(lhs::Uncertain, rhs::AffExpr) = (*)(rhs, lhs)
(/)(lhs::Uncertain, rhs::AffExpr) = error("Cannot divide uncertain by expression")
# Uncertain--Uncertain
(+)(lhs::Uncertain, rhs::Uncertain) = UAffExpr([lhs,rhs],[1.,+1.],0.)
(-)(lhs::Uncertain, rhs::Uncertain) = UAffExpr([lhs,rhs],[1.,-1.],0.)
(*)(lhs::Uncertain, rhs::Uncertain) = error("Cannot multiply two uncertains")
(/)(lhs::Uncertain, rhs::Uncertain) = error("Cannot divide two uncertains")
# Uncertain--UAffExpr
(+)(lhs::Uncertain, rhs::UAffExpr) = UAffExpr([lhs,rhs.uncs],[1.0, rhs.coeffs], rhs.constant)
(-)(lhs::Uncertain, rhs::UAffExpr) = UAffExpr([lhs,rhs.uncs],[1.0,-rhs.coeffs],-rhs.constant)
(*)(lhs::Uncertain, rhs::UAffExpr) = error("Cannot multiply uncertain and expression")
(/)(lhs::Uncertain, rhs::UAffExpr) = error("Cannot divide uncertain by expression")
# Uncertain--FullAffExpr
(+)(lhs::Uncertain, rhs::FullAffExpr) = FullAffExpr(copy(rhs.vars),copy(rhs.coeffs),lhs+rhs.constant)
(-)(lhs::Uncertain, rhs::FullAffExpr) = FullAffExpr(copy(rhs.vars),[0.0-rhs.coeffs[i] for i=1:length(rhs.coeffs)],lhs-rhs.constant)
(*)(lhs::Uncertain, rhs::FullAffExpr) = error("Cannot multiply uncertainty by uncertain expression")
(/)(lhs::Uncertain, rhs::FullAffExpr) = error("Cannot divide uncertainty by uncertain expression")

# UAffExpr
# UAffExpr--Number
(+)(lhs::UAffExpr, rhs::Number) = (+)(+rhs,lhs)
(-)(lhs::UAffExpr, rhs::Number) = (+)(-rhs,lhs)
(*)(lhs::UAffExpr, rhs::Number) = (*)( rhs,lhs)
(/)(lhs::UAffExpr, rhs::Number) = (*)(1.0/rhs,lhs)
# UAffExpr--Variable
(+)(lhs::UAffExpr, rhs::Variable) = (+)(rhs,lhs)
(-)(lhs::UAffExpr, rhs::Variable) = FullAffExpr([rhs],[UAffExpr(-1.)],lhs)
(*)(lhs::UAffExpr, rhs::Variable) = (*)(rhs,lhs)
(/)(lhs::UAffExpr, rhs::Variable) = error("Cannot divide by variable")
# UAffExpr--AffExpr
(+)(lhs::UAffExpr, rhs::AffExpr) = (+)(rhs,lhs)
(-)(lhs::UAffExpr, rhs::AffExpr) = (+)(0.0-rhs,lhs)
(*)(lhs::UAffExpr, rhs::AffExpr) = (*)(rhs,lhs)
(/)(lhs::UAffExpr, rhs::AffExpr) = error("Cannot divide by affine expression")
# UAffExpr--Uncertain
(+)(lhs::UAffExpr, rhs::Uncertain) = (+)(rhs,lhs)
(-)(lhs::UAffExpr, rhs::Uncertain) = UAffExpr([rhs,lhs.uncs],[-1.0,lhs.coeffs],lhs.constant)
(*)(lhs::UAffExpr, rhs::Uncertain) = (*)(rhs,lhs)
(/)(lhs::UAffExpr, rhs::Uncertain) = error("Cannot divide by uncertain")
# UAffExpr--UAffExpr
(+)(lhs::UAffExpr, rhs::UAffExpr) = UAffExpr([lhs.uncs,rhs.uncs],[lhs.coeffs,rhs.coeffs],lhs.constant+rhs.constant)
(-)(lhs::UAffExpr, rhs::UAffExpr) = UAffExpr([lhs.uncs,rhs.uncs],[lhs.coeffs,-rhs.coeffs],lhs.constant-rhs.constant)
(*)(lhs::UAffExpr, rhs::UAffExpr) = error("Cannot multiply two expressions")
(/)(lhs::UAffExpr, rhs::UAffExpr) = error("Cannot divide two expressions")
# UAffExpr--FullAffExpr
(+)(lhs::UAffExpr, rhs::FullAffExpr) = FullAffExpr(rhs.vars,rhs.coeffs,lhs+rhs.constant)
(-)(lhs::UAffExpr, rhs::FullAffExpr) = FullAffExpr(rhs.vars,[0.0-c for c in rhs.coeffs],lhs-rhs.constant)
(*)(lhs::UAffExpr, rhs::FullAffExpr) = error("Cannot multiply two expressions")
(/)(lhs::UAffExpr, rhs::FullAffExpr) = error("Cannot divide two expressions")

# FullAffExpr
# FullAffExpr--Number
(+)(lhs::FullAffExpr, rhs::Number) = (+)(+rhs,lhs)
(-)(lhs::FullAffExpr, rhs::Number) = (+)(-rhs,lhs)
(*)(lhs::FullAffExpr, rhs::Number) = (*)(rhs,lhs)
(/)(lhs::FullAffExpr, rhs::Number) = (*)(1.0/rhs,lhs)
# FullAffExpr--Variable
(+)(lhs::FullAffExpr, rhs::Variable) = (+)(rhs,lhs)
(-)(lhs::FullAffExpr, rhs::Variable) = FullAffExpr(vcat(lhs.vars,rhs),vcat(lhs.coeffs,UAffExpr(-1.)), lhs.constant)
(*)(lhs::FullAffExpr, rhs::Variable) = error("Cannot")
(/)(lhs::FullAffExpr, rhs::Variable) = error("Cannot")
# FullAffExpr--AffExpr
(+)(lhs::FullAffExpr, rhs::AffExpr) = (+)(rhs,lhs)
(-)(lhs::FullAffExpr, rhs::AffExpr) = FullAffExpr(
  vcat(lhs.vars, rhs.vars),
  vcat(lhs.coeffs, UAffExpr(-rhs.coeffs)),
  lhs.constant - rhs.constant)
(*)(lhs::FullAffExpr, rhs::AffExpr) = error("Cannot")
(/)(lhs::FullAffExpr, rhs::AffExpr) = error("Cannot")
# FullAffExpr--Uncertain
(+)(lhs::FullAffExpr, rhs::Uncertain) = (+)(rhs,lhs)
(-)(lhs::FullAffExpr, rhs::Uncertain) = FullAffExpr(copy(lhs.vars),copy(lhs.coeffs),lhs.constant-rhs)
(*)(lhs::FullAffExpr, rhs::Uncertain) = error("Cannot")
(/)(lhs::FullAffExpr, rhs::Uncertain) = error("Cannot")
# FullAffExpr--UAffExpr
(+)(lhs::FullAffExpr, rhs::UAffExpr) = (+)(rhs,lhs)
(-)(lhs::FullAffExpr, rhs::UAffExpr) = FullAffExpr(lhs.vars,lhs.coeffs,lhs.constant-rhs)
(*)(lhs::FullAffExpr, rhs::UAffExpr) = error("Cannot")
(/)(lhs::FullAffExpr, rhs::UAffExpr) = error("Cannot")
# FullAffExpr--FullAffExpr
(+)(lhs::FullAffExpr, rhs::FullAffExpr) = FullAffExpr(vcat(lhs.vars,rhs.vars),vcat(lhs.coeffs,rhs.coeffs),lhs.constant+rhs.constant)
(-)(lhs::FullAffExpr, rhs::FullAffExpr) = FullAffExpr(vcat(lhs.vars,rhs.vars),vcat(lhs.coeffs,[0.0-c for c in rhs.coeffs]),lhs.constant-rhs.constant)
(*)(lhs::FullAffExpr, rhs::FullAffExpr) = error("Cannot")
(/)(lhs::FullAffExpr, rhs::FullAffExpr) = error("Cannot")


include("robustsolve.jl")
include("wrangler.jl")
include("robustmacro.jl")
