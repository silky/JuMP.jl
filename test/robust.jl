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
@test affToStr(uaff) == "2.3 a + 5.5"
uaff2 = 3.4 * b + 1.1
@test affToStr(uaff2) == "3.4 b + 1.1"

faff = FullAffExpr([x],[UAffExpr([a],[5.],1.)],UAffExpr([b],[2.],3.))
@test affToStr(faff) == "(5.0 a + 1.0) x + 2.0 b + 3.0"

# 1. Number tests
# Number--Uncertain
@test affToStr(4.13 + a) == "1.0 a + 4.13"
@test affToStr(3.16 - a) == "-1.0 a + 3.16"
@test affToStr(5.23 * a) == "5.23 a"
@test_throws 2.94 / a
# Number--UAffExpr
@test affToStr(2.3 + uaff) == "2.3 a + 7.8"
@test affToStr(1.5 - uaff) == "-2.3 a + -4.0"
@test affToStr(2.0 * uaff) == "4.6 a + 11.0"
@test_throws 2.94 / uaff
# Number--FullAffExpr
@test affToStr(2.3 + faff) == "(5.0 a + 1.0) x + 2.0 b + 5.3"
@test affToStr(1.0 - faff) == "(-5.0 a + -1.0) x + -2.0 b + -2.0"
@test affToStr(2.0 * faff) == "(10.0 a + 2.0) x + 4.0 b + 6.0"
@test_throws 2.94 / faff

# 2. Variable test
# Variable--Uncertain
@test affToStr(x + a) == "(1.0) x + 1.0 a"
@test affToStr(x - a) == "(1.0) x + -1.0 a"
@test affToStr(x * a) == "(1.0 a) x + 0.0"
@test_throws affToStr(x / a)
# Variable--UAffExpr
@test affToStr(x + uaff) == "(1.0) x + 2.3 a + 5.5"
@test affToStr(x - uaff) == "(1.0) x + -2.3 a + -5.5"
@test affToStr(x * uaff) == "(2.3 a + 5.5) x + 0.0"
@test_throws affToStr(x / uaff)
# Variable--FullAffExpr
@test affToStr(x + faff) == "(5.0 a + 1.0) x + (1.0) x + 2.0 b + 3.0"
@test affToStr(x - faff) == "(-5.0 a + -1.0) x + (1.0) x + -2.0 b + -3.0"
@test_throws x * faff
@test_throws x / faff

# 3. AffExpr test
# AffExpr--Uncertain
@test affToStr(aff + a) == "(7.1) x + 1.0 a + 2.5"
@test affToStr(aff - a) == "(7.1) x + -1.0 a + 2.5"
@test affToStr(aff * a) == "(7.1 a) x + 2.5 a"
@test_throws aff / a
# AffExpr--UAffExpr
println(affToStr(aff + uaff))
println(affToStr(aff - uaff))
println(affToStr(aff * uaff))
@test_throws aff / uaff
