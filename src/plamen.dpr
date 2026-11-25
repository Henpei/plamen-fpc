program plamen;
{$mode objfpc}{$H+}
uses
  SysUtils,
  core in 'core.pas',
  raylib in 'raylib.pas';
var
  frames: Integer;
begin
  Log('PLAMEN boot commit=' + VERSION_STAMP + ' built=' + BUILD_TIME);
  if (ParamCount >= 1) and (ParamStr(1) = 'selftest') then
  begin
    Writeln('selftest: placeholder (suite not wired yet)');
    Halt(0);
  end;
  if GetEnvironmentVariable('DISPLAY') = '' then
  begin
    Writeln(StdErr, 'FATAL: no DISPLAY set - graphical mode needs an X display. ' +
      'Use ''plamen selftest'' for the headless suite. commit=' + VERSION_STAMP);
    Halt(2);
  end;
  SetConfigFlags(FLAG_WINDOW_RESIZABLE or FLAG_VSYNC_HINT);
  InitWindow(960, 540, PAnsiChar('PLAMEN ' + VERSION_STAMP));
  if not IsWindowReady then Fatal('raylib window init failed (no GL context?)');
  SetTargetFPS(60);
  SetExitKey(KEY_NULL);
  frames := 0;
  while not WindowShouldClose do
  begin
    BeginDrawing;
    ClearBackground(BLACK);
    DrawText(PAnsiChar('PLAMEN ' + VERSION_STAMP + ' - toolchain OK'), 20, 20, 20, RAYWHITE);
    EndDrawing;
    Inc(frames);
    if frames > 120 then Break;  // smoke build: exit after 120 frames
  end;
  CloseWindow;
  Log('PLAMEN exit ok');
end.
