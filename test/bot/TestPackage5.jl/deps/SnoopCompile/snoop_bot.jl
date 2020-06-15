using SnoopCompile

bcs = Vector{BotConfig}(undef, 4)

bcs[1] = BotConfig("TestPackage5", yml_path = "SnoopCompile.yml")

bcs[2] = BotConfig("TestPackage5", yml_path = "../../$(@__DIR__)/.github/workflows/SnoopCompile.yml")

bcs[3] = BotConfig("TestPackage5", yml_path = "../../.github/workflows/SnoopCompile.yml")

bcs[4] = BotConfig("TestPackage5", yml_path = ".github/workflows/SnoopCompile.yml")
