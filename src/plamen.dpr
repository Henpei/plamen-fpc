program plamen;
{$mode objfpc}{$H+}
uses
  SysUtils,
  core in 'core.pas',
  raylib in 'raylib.pas',
  selftest in 'selftest.pas',
  render in 'render.pas';
var
  frames: Integer;
begin
  Log('PLAMEN boot commit=' + VERSION_STAMP + ' built=' + BUILD_TIME);
  if (ParamCount >= 1) and (ParamStr(1) = 'selftest') then
  begin
    Halt(RunSelftest);
  end;
  if (ParamCount >= 1) and (ParamStr(1) = 'shot') then
  begin
    RunGame(True);
    Halt(0);
  end;
  if GetEnvironmentVariable('DISPLAY') = '' then
  begin
    Writeln(StdErr, 'FATAL: no DISPLAY set - graphical mode needs an X display. ' +
      'Use ''plamen selftest'' for the headless suite. commit=' + VERSION_STAMP);
    Halt(2);
  end;
  RunGame(False);
end.
