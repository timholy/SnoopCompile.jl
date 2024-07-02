using Test

using SnoopCompile

@testset "@snoop_llvm" begin

    @snoop_llvm "func_names.csv" "llvm_timings.yaml" begin
        @eval module M
            i(x) = x+5
            h(a::Array) = i(a[1]::Integer) + 2
            g(y::Integer) = h(Any[y])
        end;
        @eval M.g(3)
    end;

    times, info = SnoopCompile.read_snoop_llvm("func_names.csv", "llvm_timings.yaml")

    @test length(times) == 3  # i(), h(), g()
    @test length(info) == 3  # i(), h(), g()

    rm("func_names.csv")
    rm("llvm_timings.yaml")
end
