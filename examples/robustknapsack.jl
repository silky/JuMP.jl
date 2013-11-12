#############################################################################
# JuMP
# An algebraic modelling langauge for Julia
# See http://github.com/JuliaOpt/JuMP.jl
#############################################################################
# robustknapsack.jl
#
# Solves a robust knapsack problem:
# max sum(p_j x_j)
#  st sum(w_j x_j) <= C  forall w_j in U
#     x binary
#  U: mu_j - sd_j <= w_j <= mu_j + sd_j
#############################################################################

using JuMP

rm = RobustModel(:Max)

x = Variable[]
for i = 1:5
  push!(x, Variable(rm, 0., 1., 0, "x$i"))
end

profit = [ 5., 10., 2., 7., 4. ]
weight_mu = [ 2., 8., 4., 2., 5. ]
weight_sd = 0.5 * weight_mu
capacity = 10.

weight = Uncertain[]
for i = 1:5
  push!(weight, Uncertain(rm, weight_mu[i] - weight_sd[i], weight_mu[i] + weight_sd[i], "u$i"))
end

# Objective: maximize profit
rm.obj = sum([ profit[i]*x[i] for i=1:5 ])

# Constraint: can carry all subject to capacity
addConstraint(rm, sum([ weight[i]*x[i] for i=1:5 ]) <= capacity)

# Solve problem using MIP solver
solve(rm)

#println("Objective is: ", getObjectiveValue(rm))
println("Solution is:")
for i = 1:5
  println("x", i, " = ", getValue(x[i]))
end
