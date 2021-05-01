#####
##### Misc (usually for coverage)
#####

@testset "Base.:(+) -- SSAValues" begin
    @test (+)(Core.SSAValue(1), 1) == Core.SSAValue(2)
    @test (+)(1, Core.SSAValue(1)) == Core.SSAValue(2)
end

@testset "`walk` -- misc." begin
    v = Core.NewvarNode(Core.SlotNumber(5))
    walk(x -> x isa Core.SlotNumber ? 
         Core.SlotNumber(x.id + 1) : x, v)
end

@testset "Builder -- misc." begin
    ir = code_info(g, Int)
    p = CodeInfoTools.Builder(ir)
    for (v, st) in p
    end
    display(p)
    p = CodeInfoTools.Builder(ir)
    p = identity(p)
    get_slot(p, :x)
    println()
    println(length(p))
    println()
    slot!(p, :m)
    get_slot(p, :m)
end

@testset "code_inferred -- misc." begin
    b = CodeInfoTools.Builder(g, Int)
    identity(b)
    l = λ(finish(b), 1)
    src = code_inferred(l, Int)
    display(src)
end
