private
{
  bool isSetup = false;

  Fiber systemFiber;

  void ensureSetup()
  {
    if (isSetup) return;
    isSetup = true;

    scheduler = new FiberScheduler;

  }
}
