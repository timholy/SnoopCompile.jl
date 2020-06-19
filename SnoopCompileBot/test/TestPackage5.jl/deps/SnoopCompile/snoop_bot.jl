using SnoopCompileBot

bcs = Vector{BotConfig}(undef, 3)

bcs[1] = BotConfig("TestPackage5", yml_path = "SnoopCompile.yml")

bcs[2] = BotConfig("TestPackage5", yml_path = "../../.github/workflows/SnoopCompile.yml")

bcs[3] = BotConfig("TestPackage5", yml_path = ".github/workflows/SnoopCompile.yml")

if !( VERSION <= v"1.2" && Base.Sys.iswindows() )
    push!(bcs, BotConfig("TestPackage5", yml_path = "../../$(@__DIR__)/.github/workflows/SnoopCompile.yml"))
end
