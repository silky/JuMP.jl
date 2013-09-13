export RobustModel, Uncertain, UAffExpr, FullAffExpr
export uAffToStr, fullAffToStr

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
  solverOptions
end

# Default constructor
function RobustModel(sense::Symbol)
  if (sense != :Max && sense != :Min)
     error("Model sense must be :Max or :Min")
  end
  RobustModel(QuadExpr(),sense,
              LinearConstraint[],Any[],Any[],
              0,String[],Float64[],Float64[],Int[],
              0,String[],Float64[],Float64[],
              0,Float64[],Float64[],nothing,Dict())
end

function Variable(m::RobustModel,lower::Number,upper::Number,cat::Int,name::String)
  m.numCols += 1
  push!(m.colNames, name)
  push!(m.colLower, convert(Float64,lower))
  push!(m.colUpper, convert(Float64,upper))
  push!(m.colCat, cat)
  return Variable(m, m.numCols)
end
getName(m::RobustModel, col) = (m.colNames[col] == "" ? string("_col",col) : m.colNames[col])


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

Uncertain(m::Model,lower::Number,upper::Number) =
  Uncertain(m,lower,upper,"")

# Name setter/getters
setName(u::Uncertain,n::String) = (u.m.uncNames[v.col] = n)
getName(u::Uncertain) = (u.m.uncNames[u.unc] == "" ? string("_unc",u.unc) : u.m.uncNames[v.unc])
getNameU(m::RobustModel, unc) = (m.uncNames[unc] == "" ? string("_unc",unc) : m.uncNames[unc])
print(io::IO, u::Uncertain) = print(io, getName(u))
show(io::IO, u::Uncertain) = print(io, getName(u))

###############################################################################
# Uncertain Affine Expression class
# TODO(idunning): Can we make AffExpr parametric on a type? Or two types?
# Holds a vector of tuples (Unc, Coeff)
type UAffExpr
  uncs::Array{Uncertain,1}
  coeffs::Array{Float64,1}
  constant::Float64
end

UAffExpr() = UAffExpr(Uncertain[],Float64[],0.)
UAffExpr(c::Float64) = UAffExpr(Uncertain[],Float64[],c)
UAffExpr(u::Uncertain, c::Float64) = UAffExpr([u],[c],0.)

print(io::IO, a::UAffExpr) = print(io, uAffToStr(a))
show(io::IO, a::UAffExpr) = print(io, uAffToStr(a))

function uAffToStr(a::UAffExpr, showConstant=true)
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
# TODO(idunning): Can we make AffExpr parametric on a type? Or two types?
# TODO(idunning): Better name. In my other robust modelling tools I called it
# something like this, but the catch then was that there we only two types of
# affexpr - the one with UAffExpr coefficients = Full, and the UAffExpr itself
# Holds a vector of tuples (Unc, Coeff)
type FullAffExpr
  vars::Array{Variable,1}
  coeffs::Array{UAffExpr,1}
  constant::UAffExpr
end

FullAffExpr() = FullAffExpr(Variable[],UAffExpr[],UAffExpr())

print(io::IO, a::FullAffExpr) = print(io, fullAffToStr(a))
show(io::IO, a::FullAffExpr) = print(io, fullAffToStr(a))

# Pretty cool that this is almost the same as normal affExpr
function fullAffToStr(a::FullAffExpr, showConstant=true)
  if length(a.vars) == 0
    return string(a.constant)
  end

  # Get reference to model
  m = a.vars[1].m

  # Collect like terms
  indvec = IndexedVector(UAffExpr,m.numCols)
  for ind in 1:length(a.vars)
    addelt(indvec, a.vars[ind].col, a.coeffs[ind])
  end

  # Stringify the terms
  termStrings = Array(ASCIIString, length(a.vars))
  numTerms = 0
  for i in 1:indvec.nnz
    idx = indvec.nzidx[i]
    numTerms += 1
    termStrings[numTerms] = "$(uAffToStr(indvec.elts[idx])) $(getName(m,idx))"
  end

  # And then connect them up with +s
  ret = join(termStrings[1:numTerms], " + ")
  
  # TODO(idunning): Think more carefully about this
  #if abs(a.constant) >= 0.000001 && showConstant
  if showConstant
    ret = string(ret," + ",uAffToStr(a.constant))
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
  return ConstraintRef{UncSetConstraint}(m,length(m.uncertaintyset))
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
    return string(c.lb," <= ",uAffToStr(c.terms,false)," <= ",c.ub)
  else
    return string(uAffToStr(c.terms,false)," ",s," ",rhs(c))
  end
end

##########################################################################
# UncConstraint class
# A mix of variables and uncertains
type UncConstraint <: JuMPConstraint
  terms::FullAffExpr
  lb::Float64
  ub::Float64
end

UncConstraint(terms::FullAffExpr,lb::Number,ub::Number) =
  UncConstraint(terms,float(lb),float(ub))

function addConstraint(m::RobustModel, c::UncConstraint)
  push!(m.uncertainconstr,c)
  return ConstraintRef{UncConstraint}(m,length(m.uncertainconstr))
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
    return string(c.lb," <= ",fullAffToStr(c.terms,false)," <= ",c.ub)
  else
    return string(fullAffToStr(c.terms,false)," ",s," ",rhs(c))
  end
end

##########################################################################
# LinearConstraint class
# An affine expression with lower bound (possibly -Inf) and upper bound (possibly Inf).
function addConstraint(m::RobustModel, c::LinearConstraint)
  push!(m.certainconstr,c)
  return ConstraintRef{LinearConstraint}(m,length(m.certainconstr))
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
(/)(lhs::Number, rhs::Uncertain) = error("Cannot divide by uncertain")
# Number--UAffExpr
(+)(lhs::Number, rhs::UAffExpr) = UAffExpr(copy(rhs.uncs),copy(rhs.coeffs),lhs+rhs.constant)
(-)(lhs::Number, rhs::UAffExpr) = UAffExpr(copy(rhs.uncs),    -rhs.coeffs ,lhs-rhs.constant)
(*)(lhs::Number, rhs::UAffExpr) = UAffExpr(copy(rhs.uncs), lhs*rhs.coeffs ,lhs*rhs.constant)
(/)(lhs::Number, rhs::UAffExpr) = error("Cannot divide number by an uncertain expression")

# Variable
# Variable--Uncertain
(+)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(1.)],UAffExpr(rhs,+1.))
(-)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(1.)],UAffExpr(rhs,-1.))
(*)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(rhs,1.0)],UAffExpr())
(/)(lhs::Variable, rhs::Uncertain) = error("Cannot divide a variable by an uncertain")

# AffExpr
# AffExpr--Uncertain
(+)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars, lhs.coeffs, UAffExpr([rhs],[+1.],lhs.constant))
(-)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars, lhs.coeffs, UAffExpr([rhs],[-1.],lhs.constant))
(*)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars, [UAffExpr(rhs,lhs.coeffs[i]) for i=1:length(lhs.vars)], UAffExpr(rhs,lhs.constant))
(/)(lhs::AffExpr, rhs::Uncertain) = error("Cannot divide affine expression by an uncertain")

# Uncertain
# ...

# UAffExpr
# UAffExpr--Number
(+)(lhs::UAffExpr, rhs::Number) = (+)(+rhs,lhs)
(-)(lhs::UAffExpr, rhs::Number) = (+)(-rhs,lhs)
(*)(lhs::UAffExpr, rhs::Number) = (*)( rhs,lhs)
(/)(lhs::UAffExpr, rhs::Number) = (*)(1.0/rhs,lhs)

