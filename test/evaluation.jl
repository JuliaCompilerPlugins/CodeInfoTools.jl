#####
##### Evaluation
#####

function thunk()
    return 120
end

@testset "Evaluation - slots = (#self)" begin
    b = Builder(code_info(thunk))
    identity(b)
    fn = λ(finish(b))
    @test thunk() == fn()
end

function foo(x::Int)
    y = 0
    while x > 10
        y += 1
        x -= 1
    end
    return y
end

@testset "Evaluation - slots = (#self, :x)" begin
    b = Builder(code_info(foo, Int))
    identity(b)
    fn = λ(finish(b))
    @test foo(5) == fn(5)
end

@testset "Evaluation with nargs - slots = (#self, :x)" begin
    b = Builder(code_info(foo, Int))
    identity(b)
    fn = λ(finish(b), 1)
    @test foo(5) == fn(5)
end

foo(x::Int64, y, z) = x <= 1 ? 1 : x * foo(x - 1, y, z)

@testset "Evaluation with nargs - slots = (#self, :x, :y, :z)" begin
    b = Builder(code_info(foo, Int, Any, Any))
    identity(b)
    fn = λ(finish(b), 3)
    @test foo(5, nothing, nothing) == fn(5, nothing, nothing)
end

rosenbrock(x, y, a, b) = (a - x)^2 + b * (y - x^2)^2

@testset "Evaluation with nargs - slots = (#self, :x, :y, :a, :b)" begin
    b = Builder(code_info(rosenbrock, Float64, Float64,
                          Float64, Float64))
    identity(b)
    fn = λ(finish(b), 4)
    @test rosenbrock(1.0, 1.0, 1.0, 1.0) == fn(1.0, 1.0, 1.0, 1.0)
end

@testset "Evaluation typed with nargs - slots = (#self, :x, :y, :a, :b)" begin
    _code_info = code_typed(rosenbrock, Tuple{Float64, Float64, Float64, Float64},
                            optimize=false)[1].first
    b = Builder(_code_info)
    identity(b)
    fn = λ(finish(b), 4)
    @test rosenbrock(1.0, 1.0, 1.0, 1.0) == fn(1.0, 1.0, 1.0, 1.0)
end

@testset "Evaluation with nargs -- from lambda" begin
    l = (x, y) -> x + y
    b = Builder(l, Int, Int)
    identity(b)
    fn = λ(finish(b), 2)
    @test l(5, 5) == fn(5, 5)
end

@testset "Evaluation with nargs -- blank build" begin
    b = Builder()
    x = slot!(b, :x; arg = true)
    y = slot!(b, :y; arg = true)
    v = push!(b, Expr(:call, Base.:(+), x, y))
    return!(b, v)
    src = finish(b)
    fn = λ(src, 2)
    @test fn(5, 5) == 10
end
