using Gurobi
let
modQ = Model(solver=GurobiSolver())

@defVar(modQ, 1.1*i <= x[i=1:3] <= 2.5*i, Int)

setObjective(modQ, :Min, 3*x[1]*x[2] + x[2]*x[2] + 9*x[3]*x[1])

@addConstraint(modQ, x[2] <= 1.7*x[3])
@addConstraint(modQ, x[2] >= 0.5*x[1])

status = solve(modQ)
@test status == :Optimal
@test_approx_eq modQ.objVal 99.0
@test_approx_eq getValue(x) [2.0, 3.0, 4.0]
end

# test Maximization sense
let
modQ = Model(solver=GurobiSolver())

@defVar(modQ, 1.1*i <= x[i=1:3] <= 2.5*i, Int)

setObjective(modQ, :Max, -3*x[1]*x[2] - x[2]*x[2] - 9*x[3]*x[1])

@addConstraint(modQ, x[2] <= 1.7*x[3])
@addConstraint(modQ, x[2] >= 0.5*x[1])

status = solve(modQ)
@test status == :Optimal
@test_approx_eq modQ.objVal -99.0
@test_approx_eq getValue(x) [2.0, 3.0, 4.0]
end

let
modQ = Model(solver=GurobiSolver())

@defVar(modQ, 0.5 <= x <= 2 )
@defVar(modQ, 0 <= y <= 30 )

setObjective(modQ, :Min, (x+y)*(x+y) )
@addConstraint(modQ, x + y >= 1 )

status = solve(modQ)
@test status == :Optimal
@test_approx_eq_eps modQ.objVal 1.0 1e-6
@test_approx_eq_eps (getValue(x) + getValue(y)) 1.0 1e-6
end
