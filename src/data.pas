unit data;
{$mode objfpc}{$H+}
{ Generic data-file layer. All game content lives in data/*.dat as
  [kind:id] sections with key=value lines. Parsing errors are LOUD/FATAL
  (file:line reported). Duplicate keys are allowed (DataGetAll). }
interface

uses core;

type
  TEntry = record
    sec, key, val: string;
    line: Integer;
  end;
  TDataFile = record
    path: string;
    entries: array of TEntry;
  end;
  TDataDB = record
    files: array of TDataFile;
  end;

procedure DataLoad(var db: TDataDB; const path: string);
function DataFileIdx(const db: TDataDB; const path: string): Integer; // -1 if not loaded
function DataHas(const db: TDataDB; const path, sec, key: string): Boolean;
function DataGet(const db: TDataDB; const path, sec, key: string): string;        // FATAL if missing
function DataGetDef(const db: TDataDB; const path, sec, key, def: string): string;
function DataGetAll(const db: TDataDB; const path, sec, key: string): TStrArray;   // all values for key
function DataSecExists(const db: TDataDB; const path, sec: string): Boolean;
function DataList(const db: TDataDB; const path, kind: string): TStrArray;         // ids of [kind:id]
function DataSecs(const db: TDataDB; const path: string): TStrArray;                // all section names
{ typed helpers (FATAL on bad value) }
function DataGetI(const db: TDataDB; const path, sec, key: string): Integer;
function DataGetF(const db: TDataDB; const path, sec, key: string): Single;
function DataGetB(const db: TDataDB; const path, sec, key: string): Boolean;
function DataGetList(const db: TDataDB; const path, sec, key: string): TStrArray;  // 'a|b|c'
function DataGetIDef(const db: TDataDB; const path, sec, key: string; def: Integer): Integer;
function DataGetFDef(const db: TDataDB; const path, sec, key: string; def: Single): Single;
function DataGetBDef(const db: TDataDB; const path, sec, key: string; def: Boolean): Boolean;
function DataGetListDef(const db: TDataDB; const path, sec, key: string; const def: string): TStrArray;

implementation

uses SysUtils;

procedure DataLoad(var db: TDataDB; const path: string);
var
  txt, line: string;
  lines: TStrArray;
  i, eq, bi: Integer;
  e: TEntry;
  curSec: string;
begin
  txt := ReadTextFile(path);  // loud if missing
  SetLength(db.files, Length(db.files) + 1);
  db.files[High(db.files)].path := path;
  db.files[High(db.files)].entries := nil;
  lines := Split(txt, #10);
  curSec := '';
  for i := 0 to High(lines) do
  begin
    line := Trim(lines[i]);
    if (line = '') or (line[1] = '#') then Continue;
    if line[1] = '[' then
    begin
      bi := Pos(']', line);
      if (bi < 3) then FatalF('%s:%d: malformed section header: %s', [path, i + 1, line]);
      curSec := Copy(line, 2, bi - 2);
      Continue;
    end;
    eq := Pos('=', line);
    if eq < 2 then FatalF('%s:%d: expected key=value, got: %s', [path, i + 1, line]);
    e.sec := curSec;
    e.key := Trim(Copy(line, 1, eq - 1));
    e.val := Trim(Copy(line, eq + 1, Length(line)));
    e.line := i + 1;
    if e.key = '' then FatalF('%s:%d: empty key', [path, i + 1]);
    SetLength(db.files[High(db.files)].entries, Length(db.files[High(db.files)].entries) + 1);
    db.files[High(db.files)].entries[High(db.files[High(db.files)].entries)] := e;
  end;
end;

function DataFileIdx(const db: TDataDB; const path: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(db.files) do
    if db.files[i].path = path then Exit(i);
  Result := -1;
end;

function FindEntry(const db: TDataDB; const path, sec, key: string; out e: TEntry): Boolean;
var
  fi, i: Integer;
begin
  fi := DataFileIdx(db, path);
  if fi < 0 then FatalF('data file not loaded: %s', [path]);
  for i := 0 to High(db.files[fi].entries) do
    if (db.files[fi].entries[i].sec = sec) and (db.files[fi].entries[i].key = key) then
    begin
      e := db.files[fi].entries[i];
      Exit(True);
    end;
  Result := False;
end;

function DataHas(const db: TDataDB; const path, sec, key: string): Boolean;
var
  e: TEntry;
begin
  Result := FindEntry(db, path, sec, key, e);
end;

function DataGet(const db: TDataDB; const path, sec, key: string): string;
var
  e: TEntry;
begin
  if not FindEntry(db, path, sec, key, e) then
    FatalF('missing data: %s [%s] key=%s', [path, sec, key]);
  Result := e.val;
end;

function DataGetDef(const db: TDataDB; const path, sec, key, def: string): string;
var
  e: TEntry;
begin
  if FindEntry(db, path, sec, key, e) then Result := e.val else Result := def;
end;

function DataGetAll(const db: TDataDB; const path, sec, key: string): TStrArray;
var
  fi, i: Integer;
begin
  Result := nil;
  fi := DataFileIdx(db, path);
  if fi < 0 then FatalF('data file not loaded: %s', [path]);
  for i := 0 to High(db.files[fi].entries) do
    if (db.files[fi].entries[i].sec = sec) and (db.files[fi].entries[i].key = key) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := db.files[fi].entries[i].val;
    end;
end;

function DataSecExists(const db: TDataDB; const path, sec: string): Boolean;
var
  fi, i: Integer;
begin
  fi := DataFileIdx(db, path);
  if fi < 0 then FatalF('data file not loaded: %s', [path]);
  for i := 0 to High(db.files[fi].entries) do
    if db.files[fi].entries[i].sec = sec then Exit(True);
  Result := False;
end;

function DataList(const db: TDataDB; const path, kind: string): TStrArray;
var
  fi, i: Integer;
  sec, id: string;
  seen: array of string;
  j: Integer;
  dup: Boolean;
begin
  Result := nil;
  seen := nil;
  fi := DataFileIdx(db, path);
  if fi < 0 then FatalF('data file not loaded: %s', [path]);
  for i := 0 to High(db.files[fi].entries) do
  begin
    sec := db.files[fi].entries[i].sec;
    if StartsWith(sec, kind + ':') then
    begin
      id := Copy(sec, Length(kind) + 2, Length(sec));
      dup := False;
      for j := 0 to High(seen) do
        if seen[j] = id then begin dup := True; Break; end;
      if not dup then
      begin
        SetLength(seen, Length(seen) + 1);
        seen[High(seen)] := id;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := id;
      end;
    end;
  end;
end;

function DataSecs(const db: TDataDB; const path: string): TStrArray;
var
  fi, i, j: Integer;
  dup: Boolean;
begin
  Result := nil;
  fi := DataFileIdx(db, path);
  if fi < 0 then FatalF('data file not loaded: %s', [path]);
  for i := 0 to High(db.files[fi].entries) do
  begin
    dup := False;
    for j := 0 to High(Result) do
      if Result[j] = db.files[fi].entries[i].sec then begin dup := True; Break; end;
    if not dup then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := db.files[fi].entries[i].sec;
    end;
  end;
end;

function DataGetI(const db: TDataDB; const path, sec, key: string): Integer;
var
  v: Integer;
begin
  if not ParseIntStrict(DataGet(db, path, sec, key), v) then
    FatalF('bad int: %s [%s] %s', [path, sec, key]);
  Result := v;
end;

function DataGetF(const db: TDataDB; const path, sec, key: string): Single;
var
  v: Single;
begin
  if not ParseFloatStrict(DataGet(db, path, sec, key), v) then
    FatalF('bad float: %s [%s] %s', [path, sec, key]);
  Result := v;
end;

function DataGetB(const db: TDataDB; const path, sec, key: string): Boolean;
var
  v: Boolean;
begin
  if not ParseBoolStrict(DataGet(db, path, sec, key), v) then
    FatalF('bad bool: %s [%s] %s', [path, sec, key]);
  Result := v;
end;

function DataGetList(const db: TDataDB; const path, sec, key: string): TStrArray;
var
  parts: TStrArray;
  i: Integer;
begin
  parts := Split(DataGet(db, path, sec, key), '|');
  Result := nil;
  for i := 0 to High(parts) do
    if Trim(parts[i]) <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(parts[i]);
    end;
end;

function DataGetIDef(const db: TDataDB; const path, sec, key: string; def: Integer): Integer;
var
  v: Integer;
begin
  if not DataHas(db, path, sec, key) then Exit(def);
  if not ParseIntStrict(DataGet(db, path, sec, key), v) then
    FatalF('bad int: %s [%s] %s', [path, sec, key]);
  Result := v;
end;

function DataGetFDef(const db: TDataDB; const path, sec, key: string; def: Single): Single;
var
  v: Single;
begin
  if not DataHas(db, path, sec, key) then Exit(def);
  if not ParseFloatStrict(DataGet(db, path, sec, key), v) then
    FatalF('bad float: %s [%s] %s', [path, sec, key]);
  Result := v;
end;

function DataGetBDef(const db: TDataDB; const path, sec, key: string; def: Boolean): Boolean;
var
  v: Boolean;
begin
  if not DataHas(db, path, sec, key) then Exit(def);
  if not ParseBoolStrict(DataGet(db, path, sec, key), v) then
    FatalF('bad bool: %s [%s] %s', [path, sec, key]);
  Result := v;
end;

function DataGetListDef(const db: TDataDB; const path, sec, key: string; const def: string): TStrArray;
var
  parts: TStrArray;
  i: Integer;
begin
  if not DataHas(db, path, sec, key) then
  begin
    if def = '' then Exit(nil);
    parts := Split(def, '|');
  end
  else
    parts := Split(DataGet(db, path, sec, key), '|');
  Result := nil;
  for i := 0 to High(parts) do
    if Trim(parts[i]) <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(parts[i]);
    end;
end;

end.
