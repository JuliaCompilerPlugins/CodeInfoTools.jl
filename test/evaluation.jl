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
