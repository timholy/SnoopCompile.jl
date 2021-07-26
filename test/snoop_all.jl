using Test

using SnoopCompile

f(x) = 2^x + 100

@testset "basic snoop_all" begin
    # First time not empty
    tinf = SnoopCompileCore.@snoop_all "snoopl.csv" "snoopl.yaml" "snoopc.csv" f(2)

    @test length(collect(flatten(tinf))) > 1
    @test filesize("snoopl.csv") != 0
    @test filesize("snoopl.yaml") != 0
    @test filesize("snoopc.csv") != 0

    rm("snoopl.csv")
    rm("snoopl.yaml")
    rm("snoopc.csv")

    # Second run is empty because f(x) is already compiled
    tinf = SnoopCompileCore.@snoop_all "snoopl.csv" "snoopl.yaml" "snoopc.csv" f(2)

    @test length(collect(flatten(tinf))) == 1
    @test filesize("snoopl.csv") == 0
    @test filesize("snoopl.yaml") == 0
    @test filesize("snoopc.csv") == 0

    rm("snoopl.csv")
    rm("snoopl.yaml")
    rm("snoopc.csv")
end

