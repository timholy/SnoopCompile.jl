using SnoopCompileBot

# using runtests:
snoop_bot(BotConfig("TestPackage4"), "$(@__DIR__)/example_script.jl")
