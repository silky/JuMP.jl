using JuMP
using Base.Test

m = RobustModel(:Max)
@defVar(m, w)
@defVar(m, x)
@defVar(m, y)
@defVar(m, z)

aff = 7.1 * x + 2.5
@test affToStr(aff) == "7.1 x + 2.5"

aff2 = 1.2 * y + 1.2
@test affToStr(aff2) == "1.2 y + 1.2"

a = Uncertain(m, 2.0, 3.0, "a")
b = Uncertain(m, 5.0, 6.0, "b")

uaff = 2.3 * a + 5.5
@test uAffToStr(uaff) == "2.3 a + 5.5"
uaff2 = 3.4 * b + 1.1
@test uAffToStr(uaff2) == "3.4 b + 1.1"

# 1. Number tests
# Number--Uncertain
@test uAffToStr(4.13 + a) == "1.0 a + 4.13"
@test uAffToStr(3.16 - a) == "-1.0 a + 3.16"
@test uAffToStr(5.23 * a) == "5.23 a"
@test_throws 2.94 / a
# Number--UAffExpr
@test uAffToStr(2.3 + uaff) == "2.3 a + 7.8"
@test uAffToStr(1.5 - uaff) == "-2.3 a + -4.0"
@test uAffToStr(2.0 * uaff) == "4.6 a + 11.0"
@test_throws 2.94 / uaff


# Variable--Uncertain
#(+)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(1.)],UAffExpr(rhs,+1.))
#(-)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(1.)],UAffExpr(rhs,-1.))
#(*)(lhs::Variable, rhs::Uncertain) = FullAffExpr([lhs],[UAffExpr(rhs,1.0)],UAffExpr())
#(/)(lhs::Variable, rhs::Uncertain) = error("Cannot divide a variable by an uncertain")

# AffExpr--Uncertain
#(+)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars, lhs.coeffs, UAffExpr([rhs],[+1.],lhs.constant))
#(-)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars, lhs.coeffs, UAffExpr([rhs],[-1.],lhs.constant))
#(*)(lhs::AffExpr, rhs::Uncertain) = FullAffExpr(lhs.vars, [UAffExpr(rhs,lhs.coeffs[i]) for i=1:length(lhs.vars)], UAffExpr(rhs,lhs.constant))
#(/)(lhs::AffExpr, rhs::Uncertain) = error("Cannot divide affine expression by an uncertain")

