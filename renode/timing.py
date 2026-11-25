# Prints how well the control loop keeps its deadline. blackbox.resc runs it
# from `runMacro $timing`.
#
# The counters are LOOP_TIMING's fields in order, and TIM3's ARR + 1 is the
# counts in one period.

TIM3_ARR = 0x4000042C

bus = monitor.Machine.SystemBus
base = bus.GetSymbolAddress("LOOP_TIMING")


def field(index):
    return bus.ReadDoubleWord(base + 4 * index)


counts = bus.ReadDoubleWord(TIM3_ARR) + 1
print("ticks %d, overruns %d, max jitter %d ns"
      % (field(0), field(1), field(2) * 1000000 // counts))
