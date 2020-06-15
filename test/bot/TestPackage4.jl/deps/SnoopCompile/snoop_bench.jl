using SnoopCompile

println("tests infer benchmark")

exmaple_path = joinpath(dirname(dirname(pathof_noload("TestPackage4"))), "src", "example_script.jl")
snoop_bench(BotConfig("TestPackage4"), exmaple_path)
