using SnoopCompile

# using runtests:
@snoopi_bot BotConfig("TestPackage3", version = [v"1.1", v"1.4.1"], else_version = v"1.1")
