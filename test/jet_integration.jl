using Test
using JET
using SnoopCompile

if Base.VERSION >= v"1.7"
    @testset "JET integration" begin
        f(c) = sum(c[1])
        c = Any[Any[1,2,3]]
        tinf = @snoopi_deep f(c)
        rpt = JET.@report_call f(c)
        @test isempty(JET.get_reports(rpt))
        itrigs = inference_triggers(tinf)
        irpts = report_callees(itrigs)
        @test only(irpts).first == last(itrigs)
        @test !isempty(JET.get_reports(only(irpts).second))
        @test  isempty(JET.get_reports(report_caller(itrigs[end])))
    end
end
