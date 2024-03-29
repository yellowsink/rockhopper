import std.stdio;
import std.datetime : dur;

import reactor : spawn, entrypoint;
import events : sleep;

void main()
{
  entrypoint(&mainAsync);
  writeln("end of main()");
}

void mainAsync()
{
  spawn({
    writeln("i'm number 1! hi!");
    sleep(dur!"msecs"(4000));
    writeln("number 1 slept for 4s");
  });

  spawn({
    writeln("i'm number 2! hi!");
    sleep(dur!"msecs"(2500));
    writeln("number 2 slept for 2.5s");
  });

  //writeln("mainAsync() about to sleep for 10s...");
  //sleep(dur!"msecs"(10_000));
  // this DOESNT work

  writeln("end of mainAsync()");
}
