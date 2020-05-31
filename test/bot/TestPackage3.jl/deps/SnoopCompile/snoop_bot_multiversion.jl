using SnoopCompile

# using runtests:
snoop_bot(BotConfig("TestPackage3", version = [v"1.2", v"1.4.2"], else_version = v"1.2"))
