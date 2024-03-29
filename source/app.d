import std.stdio;
import std.datetime : dur;

import reactor : spawn, entrypoint, earlyExit;
import events : sleep, fileRead;

void main()
{
  entrypoint(&mainAsync);
  writeln("end of main()");
}

void mainAsync()
{
  import std.string : assumeUTF, stripRight;

  writeln("reading");
  auto buf = new ubyte[100];
  auto res = fileRead("dub.json", 0, buf);
  writeln("status: ", res[0]);
  writeln("read amt: ", res[1]);
  writeln("buffer: ", stripRight(buf.assumeUTF, "\0"));
}

/* void mainAsync()
{
  spawn({
    writeln("i'm number 1! hi!");
    sleep(dur!"msecs"(4000));
    writeln("number 1 slept for 4s");
  });

  spawn({
    writeln("i'm number 2! hi!");
    //earlyExit();
    sleep(dur!"msecs"(2500));
    writeln("number 2 slept for 2.5s");
  });

  writeln("mainAsync() about to sleep for 500ms...");
  sleep(dur!"msecs"(500));

  writeln("end of mainAsync()");
} */
