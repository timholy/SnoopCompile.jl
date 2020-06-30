using SnoopCompile # for backward compatibiity test

println("tests infer benchmark")

exmaple_path = joinpath(dirname(dirname(SnoopCompile.pathof_noload("TestPackage4"))), "src", "example_script.jl")
snoop_bench(BotConfig("TestPackage4"), exmaple_path)
