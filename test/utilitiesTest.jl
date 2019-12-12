using SnoopCompile, Test


@testset "utilities" begin
    answer = precompilePath("MatLang")
    @test  answer == "\"../deps/SnoopCompile/precompile/precompile_MatLang.jl\""

end
