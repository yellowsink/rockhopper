import std.stdio;
import std.datetime : dur;

import reactor : spawn, entrypoint, earlyExit, yield;
import events : sleep, fileRead, fileOpen, FileOpenMode;

import core.sys.posix.unistd : isatty, STDIN_FILENO;
import core.sys.posix.termios : tcsetattr, tcgetattr, termios, TCSANOW;

extern (C) void cfmakeraw(termios*);

void main() { entrypoint(&mainAsync); }

void mainAsync()
{
  // background fiber
  spawn({
    while (true) {
      writeln("\033[Gboop.");
      sleep(dur!"msecs"(1000));
    }
  });

  import std.string : assumeUTF, stripRight;

  // raw mode
  assert(isatty(STDIN_FILENO));
  termios optsBackup;
  termios optsRaw;

  tcgetattr(STDIN_FILENO, &optsBackup);
  cfmakeraw(&optsRaw);
  tcsetattr(STDIN_FILENO, TCSANOW, &optsRaw);

  //auto openRes = fileOpen("/dev/stdin", FileOpenMode.read);
  //writeln("opened stdin: ", openRes[1]);
  import eventcore.core : eventDriver;
  auto stdin = eventDriver.files.adopt(STDIN_FILENO);

  while (true) {
    auto buf = new ubyte[1];
    auto readRes = fileRead(stdin, 0, buf);
    auto bufStr = buf.assumeUTF;
    if (bufStr[0] == 'd') {
      writeln("\033[GI got a 'd', I'm outta here!");
      // raw mode off
      tcsetattr(STDIN_FILENO, TCSANOW, &optsBackup);
      earlyExit();
    }

    writeln("\033[Ggot a char!", bufStr, " ", readRes[1]);
  }
}
