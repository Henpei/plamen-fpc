unit raylib;
{$mode objfpc}{$H+}
interface
{$linklib raylib}

type
  PVector2 = ^TVector2;
  TVector2 = record x, y: Single; end;
  TRectangle = record x, y, width, height: Single; end;
  PColor = ^TColor;
  TColor = record r, g, b, a: Byte; end;
  PImage = ^TImage;
  TImage = record data: Pointer; width, height, mipmaps, format: Integer; end;
  TTexture2D = record id: LongWord; width, height, mipmaps, format: Integer; end;
  TRenderTexture2D = record id: LongWord; texture, depth: TTexture2D; end;
  PRectangle = ^TRectangle;
  PGlyphInfo = ^TGlyphInfo;
  TGlyphInfo = record value, offsetX, offsetY, advanceX: Integer; image: TImage; end;
  TFont = record
    baseSize, glyphCount, glyphPadding: Integer;
    texture: TTexture2D;
    recs: PRectangle;
    glyphs: PGlyphInfo;
  end;
  TCamera2D = record offset, target: TVector2; rotation, zoom: Single; end;
  PVector3 = ^TVector3;
  TVector3 = record x, y, z: Single; end;
  TVector4 = record x, y, z, w: Single; end;
  TMatrix = record
    m0, m4, m8, m12: Single;
    m1, m5, m9, m13: Single;
    m2, m6, m10, m14: Single;
    m3, m7, m11, m15: Single;
  end;
  PMatrix = ^TMatrix;
  TRay = record position, direction: TVector3; end;
  TRayCollision = record hit: Boolean; distance: Single; point, normal: TVector3; end;
  TBoundingBox = record min, max: TVector3; end;
  TCamera3D = record
    position, target, up: TVector3;
    fovy: Single;        // perspective: degrees; orthographic: near plane height in world units
    projection: Integer; // CAMERA_PERSPECTIVE / CAMERA_ORTHOGRAPHIC
  end;
  TShader = record id: LongWord; locs: PInteger; end;
  PMaterialMap = ^TMaterialMap;
  TMaterialMap = record texture: TTexture2D; color: TColor; value: Single; end;
  TMaterial = record shader: TShader; maps: PMaterialMap; params: array[0..3] of Single; end;
  PMaterial = ^TMaterial;
  PMesh = ^TMesh;
  TMesh = record
    vertexCount, triangleCount: Integer;
    vertices, texcoords, texcoords2, normals, tangents: PSingle;
    colors: PByte;
    indices: PWord;
    boneCount: Integer;
    boneIndices: PByte;
    boneWeights: PSingle;
    animVertices, animNormals: PSingle;
    vaoId: LongWord;
    vboId: PLongWord;
  end;
  TModelSkeleton = record boneCount: LongWord; bones, bindPose: Pointer; end;
  TModel = record
    transform: TMatrix;
    meshCount, materialCount: Integer;
    meshes: PMesh;
    materials: PMaterial;
    meshMaterial: PInteger;
    skeleton: TModelSkeleton;
    currentPose: Pointer;
    boneMatrices: PMatrix;
  end;

const
  // ConfigFlags
  FLAG_VSYNC_HINT       = $00000040;
  FLAG_FULLSCREEN_MODE  = $00000002;
  FLAG_WINDOW_RESIZABLE = $00000004;
  FLAG_MSAA_4X_HINT     = $00000020;
  FLAG_WINDOW_HIGHDPI   = $00002000;
  // TraceLogLevel
  LOG_ALL = 0; LOG_TRACE = 1; LOG_DEBUG = 2; LOG_INFO = 3; LOG_WARNING = 4; LOG_ERROR = 5; LOG_FATAL = 6; LOG_NONE = 7;
  // TextureFilter
  TEXTURE_FILTER_POINT = 0;
  TEXTURE_FILTER_BILINEAR = 1;
  // TextureWrap
  TEXTURE_WRAP_REPEAT = 0;
  TEXTURE_WRAP_CLAMP = 1;
  // CameraProjection
  CAMERA_PERSPECTIVE = 0;
  CAMERA_ORTHOGRAPHIC = 1;
  // MaterialMapIndex
  MATERIAL_MAP_ALBEDO = 0;
  // ShaderUniformDataType
  SHADER_UNIFORM_FLOAT = 0;
  SHADER_UNIFORM_VEC2 = 1;
  SHADER_UNIFORM_VEC3 = 2;
  SHADER_UNIFORM_VEC4 = 3;
  SHADER_UNIFORM_INT = 4;
  // BlendMode
  BLEND_ALPHA = 0;
  BLEND_ADDITIVE = 1;
  // MouseButton
  MOUSE_BUTTON_LEFT = 0; MOUSE_BUTTON_RIGHT = 1; MOUSE_BUTTON_MIDDLE = 2;
  // KeyboardKey (subset)
  KEY_NULL = 0; KEY_SPACE = 32; KEY_APOSTROPHE = 39; KEY_COMMA = 44; KEY_MINUS = 45;
  KEY_PERIOD = 46; KEY_SLASH = 47; KEY_ZERO = 48; KEY_ONE = 49; KEY_TWO = 50;
  KEY_THREE = 51; KEY_FOUR = 52; KEY_FIVE = 53; KEY_SIX = 54; KEY_SEVEN = 55;
  KEY_EIGHT = 56; KEY_NINE = 57; KEY_SEMICOLON = 59; KEY_EQUAL = 61;
  KEY_A = 65; KEY_B = 66; KEY_C = 67; KEY_D = 68; KEY_E = 69; KEY_F = 70; KEY_G = 71;
  KEY_H = 72; KEY_I = 73; KEY_J = 74; KEY_K = 75; KEY_L = 76; KEY_M = 77; KEY_N = 78;
  KEY_O = 79; KEY_P = 80; KEY_Q = 81; KEY_R = 82; KEY_S = 83; KEY_T = 84; KEY_U = 85;
  KEY_V = 86; KEY_W = 87; KEY_X = 88; KEY_Y = 89; KEY_Z = 90;
  KEY_LEFT_BRACKET = 91; KEY_BACKSLASH = 92; KEY_RIGHT_BRACKET = 93; KEY_GRAVE = 96;
  KEY_ESCAPE = 256; KEY_ENTER = 257; KEY_TAB = 258; KEY_BACKSPACE = 259; KEY_INSERT = 260;
  KEY_DELETE = 261; KEY_RIGHT = 262; KEY_LEFT = 263; KEY_DOWN = 264; KEY_UP = 265;
  KEY_PAGE_UP = 266; KEY_PAGE_DOWN = 267; KEY_HOME = 268; KEY_END = 269;
  KEY_CAPS_LOCK = 280; KEY_PRINT_SCREEN = 283; KEY_PAUSE = 284;
  KEY_F1 = 290; KEY_F2 = 291; KEY_F3 = 292; KEY_F4 = 293; KEY_F5 = 294; KEY_F6 = 295;
  KEY_F7 = 296; KEY_F8 = 297; KEY_F9 = 298; KEY_F10 = 299; KEY_F11 = 300; KEY_F12 = 301;
  KEY_LEFT_SHIFT = 340; KEY_LEFT_CONTROL = 341; KEY_LEFT_ALT = 342; KEY_LEFT_SUPER = 343;
  KEY_RIGHT_SHIFT = 344; KEY_RIGHT_CONTROL = 345; KEY_RIGHT_ALT = 346;
  KEY_KP_0 = 320; KEY_KP_1 = 321; KEY_KP_2 = 322; KEY_KP_3 = 323; KEY_KP_4 = 324;
  KEY_KP_5 = 325; KEY_KP_6 = 326; KEY_KP_7 = 327; KEY_KP_8 = 328; KEY_KP_9 = 329;
  KEY_KP_DECIMAL = 330; KEY_KP_DIVIDE = 331; KEY_KP_MULTIPLY = 332; KEY_KP_SUBTRACT = 333;
  KEY_KP_ADD = 334; KEY_KP_ENTER = 335; KEY_KP_EQUAL = 336;

const
  LIGHTGRAY: TColor = (r: 200; g: 200; b: 200; a: 255);
  GRAY: TColor = (r: 130; g: 130; b: 130; a: 255);
  DARKGRAY: TColor = (r: 80; g: 80; b: 80; a: 255);
  YELLOW: TColor = (r: 253; g: 249; b: 0; a: 255);
  GOLD: TColor = (r: 255; g: 203; b: 0; a: 255);
  ORANGE: TColor = (r: 255; g: 161; b: 0; a: 255);
  PINK: TColor = (r: 255; g: 109; b: 194; a: 255);
  RED: TColor = (r: 230; g: 41; b: 55; a: 255);
  MAROON: TColor = (r: 190; g: 33; b: 55; a: 255);
  GREEN: TColor = (r: 0; g: 228; b: 48; a: 255);
  LIME: TColor = (r: 0; g: 158; b: 47; a: 255);
  DARKGREEN: TColor = (r: 0; g: 117; b: 44; a: 255);
  SKYBLUE: TColor = (r: 102; g: 191; b: 255; a: 255);
  BLUE: TColor = (r: 0; g: 121; b: 241; a: 255);
  DARKBLUE: TColor = (r: 0; g: 82; b: 172; a: 255);
  PURPLE: TColor = (r: 200; g: 122; b: 255; a: 255);
  VIOLET: TColor = (r: 135; g: 60; b: 190; a: 255);
  DARKPURPLE: TColor = (r: 112; g: 50; b: 160; a: 255);
  BEIGE: TColor = (r: 211; g: 176; b: 131; a: 255);
  BROWN: TColor = (r: 127; g: 106; b: 79; a: 255);
  DARKBROWN: TColor = (r: 76; g: 63; b: 47; a: 255);
  WHITE: TColor = (r: 255; g: 255; b: 255; a: 255);
  BLACK: TColor = (r: 0; g: 0; b: 0; a: 255);
  BLANK: TColor = (r: 0; g: 0; b: 0; a: 0);
  MAGENTA: TColor = (r: 255; g: 0; b: 255; a: 255);
  RAYWHITE: TColor = (r: 245; g: 245; b: 245; a: 255);

// Window / timing
procedure InitWindow(width, height: Integer; const title: PAnsiChar); cdecl; external 'raylib' name 'InitWindow';
procedure CloseWindow; cdecl; external 'raylib' name 'CloseWindow';
function WindowShouldClose: Boolean; cdecl; external 'raylib' name 'WindowShouldClose';
function IsWindowReady: Boolean; cdecl; external 'raylib' name 'IsWindowReady';
procedure SetTargetFPS(fps: Integer); cdecl; external 'raylib' name 'SetTargetFPS';
function GetFPS: Integer; cdecl; external 'raylib' name 'GetFPS';
function GetTime: Double; cdecl; external 'raylib' name 'GetTime';
function GetFrameTime: Single; cdecl; external 'raylib' name 'GetFrameTime';
procedure SetConfigFlags(flags: LongWord); cdecl; external 'raylib' name 'SetConfigFlags';
procedure SetTraceLogLevel(logLevel: Integer); cdecl; external 'raylib' name 'SetTraceLogLevel';
procedure SetExitKey(key: Integer); cdecl; external 'raylib' name 'SetExitKey';
function GetScreenWidth: Integer; cdecl; external 'raylib' name 'GetScreenWidth';
function GetScreenHeight: Integer; cdecl; external 'raylib' name 'GetScreenHeight';
procedure SetWindowTitle(const title: PAnsiChar); cdecl; external 'raylib' name 'SetWindowTitle';
procedure SetWindowSize(width, height: Integer); cdecl; external 'raylib' name 'SetWindowSize';
procedure SetWindowMinSize(width, height: Integer); cdecl; external 'raylib' name 'SetWindowMinSize';
procedure ToggleFullscreen; cdecl; external 'raylib' name 'ToggleFullscreen';
function IsWindowFullscreen: Boolean; cdecl; external 'raylib' name 'IsWindowFullscreen';
procedure TakeScreenshot(const fileName: PAnsiChar); cdecl; external 'raylib' name 'TakeScreenshot';
function FileExists(const fileName: PAnsiChar): Boolean; cdecl; external 'raylib' name 'FileExists';
function GetApplicationDirectory: PAnsiChar; cdecl; external 'raylib' name 'GetApplicationDirectory';

// Drawing
procedure BeginDrawing; cdecl; external 'raylib' name 'BeginDrawing';
procedure EndDrawing; cdecl; external 'raylib' name 'EndDrawing';
procedure ClearBackground(color: TColor); cdecl; external 'raylib' name 'ClearBackground';
procedure BeginMode2D(camera: TCamera2D); cdecl; external 'raylib' name 'BeginMode2D';
procedure EndMode2D; cdecl; external 'raylib' name 'EndMode2D';
procedure BeginTextureMode(target: TRenderTexture2D); cdecl; external 'raylib' name 'BeginTextureMode';
procedure EndTextureMode; cdecl; external 'raylib' name 'EndTextureMode';

// Input
function IsKeyDown(key: Integer): Boolean; cdecl; external 'raylib' name 'IsKeyDown';
function IsKeyPressed(key: Integer): Boolean; cdecl; external 'raylib' name 'IsKeyPressed';
function IsKeyPressedRepeat(key: Integer): Boolean; cdecl; external 'raylib' name 'IsKeyPressedRepeat';
function IsKeyReleased(key: Integer): Boolean; cdecl; external 'raylib' name 'IsKeyReleased';
function GetKeyPressed: Integer; cdecl; external 'raylib' name 'GetKeyPressed';
function GetCharPressed: Integer; cdecl; external 'raylib' name 'GetCharPressed';
function IsMouseButtonDown(button: Integer): Boolean; cdecl; external 'raylib' name 'IsMouseButtonDown';
function IsMouseButtonPressed(button: Integer): Boolean; cdecl; external 'raylib' name 'IsMouseButtonPressed';
function GetMousePosition: TVector2; cdecl; external 'raylib' name 'GetMousePosition';
function GetMouseDelta: TVector2; cdecl; external 'raylib' name 'GetMouseDelta';
function GetMouseWheelMove: Single; cdecl; external 'raylib' name 'GetMouseWheelMove';
procedure SetMousePosition(x, y: Integer); cdecl; external 'raylib' name 'SetMousePosition';
procedure HideCursor; cdecl; external 'raylib' name 'HideCursor';
procedure ShowCursor; cdecl; external 'raylib' name 'ShowCursor';

// Shapes
procedure DrawPixel(posX, posY: Integer; color: TColor); cdecl; external 'raylib' name 'DrawPixel';
procedure DrawLine(startPosX, startPosY, endPosX, endPosY: Integer; color: TColor); cdecl; external 'raylib' name 'DrawLine';
procedure DrawLineEx(startPos, endPos: TVector2; thick: Single; color: TColor); cdecl; external 'raylib' name 'DrawLineEx';
procedure DrawTriangle(v1, v2, v3: TVector2; color: TColor); cdecl; external 'raylib' name 'DrawTriangle';
procedure DrawTriangleFan(points: PVector2; pointCount: Integer; color: TColor); cdecl; external 'raylib' name 'DrawTriangleFan';
procedure DrawRectangle(posX, posY, width, height: Integer; color: TColor); cdecl; external 'raylib' name 'DrawRectangle';
procedure DrawRectangleRec(rec: TRectangle; color: TColor); cdecl; external 'raylib' name 'DrawRectangleRec';
procedure DrawRectanglePro(rec: TRectangle; origin: TVector2; rotation: Single; color: TColor); cdecl; external 'raylib' name 'DrawRectanglePro';
procedure DrawRectangleLines(posX, posY, width, height: Integer; color: TColor); cdecl; external 'raylib' name 'DrawRectangleLines';
procedure DrawRectangleLinesEx(rec: TRectangle; thick: Single; color: TColor); cdecl; external 'raylib' name 'DrawRectangleLinesEx';
procedure DrawRectangleGradientV(posX, posY, width, height: Integer; top, bottom: TColor); cdecl; external 'raylib' name 'DrawRectangleGradientV';
procedure DrawRectangleRounded(rec: TRectangle; roundness: Single; segments: Integer; color: TColor); cdecl; external 'raylib' name 'DrawRectangleRounded';
procedure DrawRectangleRoundedLinesEx(rec: TRectangle; roundness: Single; segments: Integer; thick: Single; color: TColor); cdecl; external 'raylib' name 'DrawRectangleRoundedLinesEx';
procedure DrawCircle(centerX, centerY: Integer; radius: Single; color: TColor); cdecl; external 'raylib' name 'DrawCircle';
procedure DrawCircleV(center: TVector2; radius: Single; color: TColor); cdecl; external 'raylib' name 'DrawCircleV';
procedure DrawCircleGradient(centerX, centerY: Integer; radius: Single; inner, outer: TColor); cdecl; external 'raylib' name 'DrawCircleGradient';
procedure DrawCircleLines(centerX, centerY: Integer; radius: Single; color: TColor); cdecl; external 'raylib' name 'DrawCircleLines';
procedure DrawCircleLinesV(center: TVector2; radius: Single; color: TColor); cdecl; external 'raylib' name 'DrawCircleLinesV';
procedure DrawRing(center: TVector2; innerRadius, outerRadius, startAngle, endAngle: Single; segments: Integer; color: TColor); cdecl; external 'raylib' name 'DrawRing';
procedure DrawPoly(center: TVector2; sides: Integer; radius, rotation: Single; color: TColor); cdecl; external 'raylib' name 'DrawPoly';
procedure DrawPolyLines(center: TVector2; sides: Integer; radius, rotation: Single; color: TColor); cdecl; external 'raylib' name 'DrawPolyLines';

// Text
function LoadFontEx(const fileName: PAnsiChar; fontSize: Integer; codepoints: PInteger; codepointCount: Integer): TFont; cdecl; external 'raylib' name 'LoadFontEx';
function GetFontDefault: TFont; cdecl; external 'raylib' name 'GetFontDefault';
procedure UnloadFont(font: TFont); cdecl; external 'raylib' name 'UnloadFont';
function IsFontValid(font: TFont): Boolean; cdecl; external 'raylib' name 'IsFontValid';
procedure DrawText(const text: PAnsiChar; posX, posY, fontSize: Integer; color: TColor); cdecl; external 'raylib' name 'DrawText';
procedure DrawTextEx(font: TFont; const text: PAnsiChar; position: TVector2; fontSize, spacing: Single; tint: TColor); cdecl; external 'raylib' name 'DrawTextEx';
function MeasureText(const text: PAnsiChar; fontSize: Integer): Integer; cdecl; external 'raylib' name 'MeasureText';
function MeasureTextEx(font: TFont; const text: PAnsiChar; fontSize, spacing: Single): TVector2; cdecl; external 'raylib' name 'MeasureTextEx';
procedure DrawFPS(posX, posY: Integer); cdecl; external 'raylib' name 'DrawFPS';
function TextLength(const text: PAnsiChar): LongWord; cdecl; external 'raylib' name 'TextLength';

// Textures / images
function GenImageColor(width, height: Integer; color: TColor): TImage; cdecl; external 'raylib' name 'GenImageColor';
function LoadTextureFromImage(image: TImage): TTexture2D; cdecl; external 'raylib' name 'LoadTextureFromImage';
procedure UnloadTexture(texture: TTexture2D); cdecl; external 'raylib' name 'UnloadTexture';
procedure UnloadImage(image: TImage); cdecl; external 'raylib' name 'UnloadImage';
procedure SetTextureFilter(texture: TTexture2D; filter: Integer); cdecl; external 'raylib' name 'SetTextureFilter';
function LoadRenderTexture(width, height: Integer): TRenderTexture2D; cdecl; external 'raylib' name 'LoadRenderTexture';
procedure UnloadRenderTexture(target: TRenderTexture2D); cdecl; external 'raylib' name 'UnloadRenderTexture';
procedure DrawTexture(texture: TTexture2D; posX, posY: Integer; tint: TColor); cdecl; external 'raylib' name 'DrawTexture';
procedure DrawTexturePro(texture: TTexture2D; srcrec, dstrec: TRectangle; origin: TVector2; rotation: Single; tint: TColor); cdecl; external 'raylib' name 'DrawTexturePro';
procedure DrawTextureRec(texture: TTexture2D; rec: TRectangle; position: TVector2; tint: TColor); cdecl; external 'raylib' name 'DrawTextureRec';
procedure ImageDrawRectangle(dst: PImage; posX, posY, width, height: Integer; color: TColor); cdecl; external 'raylib' name 'ImageDrawRectangle';
procedure ImageDrawRectangleLines(dst: PImage; posX, posY, width, height: Integer; color: TColor); cdecl; external 'raylib' name 'ImageDrawRectangleLines';
procedure ImageDrawCircleV(dst: PImage; center: TVector2; radius: Integer; color: TColor); cdecl; external 'raylib' name 'ImageDrawCircleV';
procedure ImageDrawCircleLinesV(dst: PImage; center: TVector2; radius: Integer; color: TColor); cdecl; external 'raylib' name 'ImageDrawCircleLinesV';
procedure ImageDrawLine(dst: PImage; startPosX, startPosY, endPosX, endPosY: Integer; color: TColor); cdecl; external 'raylib' name 'ImageDrawLine';
procedure ImageDrawTriangle(dst: PImage; v1, v2, v3: TVector2; color: TColor); cdecl; external 'raylib' name 'ImageDrawTriangle';
procedure ImageDrawTextEx(dst: PImage; font: TFont; const text: PAnsiChar; position: TVector2; fontSize, spacing: Single; tint: TColor); cdecl; external 'raylib' name 'ImageDrawTextEx';

// Misc
function GetRandomValue(min, max: Integer): Integer; cdecl; external 'raylib' name 'GetRandomValue';
function Fade(color: TColor; alpha: Single): TColor; cdecl; external 'raylib' name 'Fade';
function ColorAlpha(color: TColor; alpha: Single): TColor; cdecl; external 'raylib' name 'ColorAlpha';
function GetColor(hexValue: LongWord): TColor; cdecl; external 'raylib' name 'GetColor';
function CheckCollisionRecs(rec1, rec2: TRectangle): Boolean; cdecl; external 'raylib' name 'CheckCollisionRecs';
function CheckCollisionPointRec(point: TVector2; rec: TRectangle): Boolean; cdecl; external 'raylib' name 'CheckCollisionPointRec';
function CheckCollisionPointCircle(point, center: TVector2; radius: Single): Boolean; cdecl; external 'raylib' name 'CheckCollisionPointCircle';

// 3D mode / camera / picking
procedure BeginMode3D(camera: TCamera3D); cdecl; external 'raylib' name 'BeginMode3D';
procedure EndMode3D; cdecl; external 'raylib' name 'EndMode3D';
function GetScreenToWorldRay(mousePosition: TVector2; camera: TCamera3D): TRay; cdecl; external 'raylib' name 'GetScreenToWorldRay';
function GetWorldToScreen(position: TVector3; camera: TCamera3D): TVector2; cdecl; external 'raylib' name 'GetWorldToScreen';
function MatrixTranslate(x, y, z: Single): TMatrix; cdecl; external 'raylib' name 'MatrixTranslate';
function MatrixScale(x, y, z: Single): TMatrix; cdecl; external 'raylib' name 'MatrixScale';
function MatrixRotateX(angle: Single): TMatrix; cdecl; external 'raylib' name 'MatrixRotateX';
function MatrixRotateZ(angle: Single): TMatrix; cdecl; external 'raylib' name 'MatrixRotateZ';
function MatrixMultiply(left, right: TMatrix): TMatrix; cdecl; external 'raylib' name 'MatrixMultiply';
function MatrixRotate(axis: TVector3; angle: Single): TMatrix; cdecl; external 'raylib' name 'MatrixRotate';
function MatrixLookAt(eye, target, up: TVector3): TMatrix; cdecl; external 'raylib' name 'MatrixLookAt';
function MatrixOrtho(left, right, bottom, top, nearPlane, farPlane: Double): TMatrix; cdecl; external 'raylib' name 'MatrixOrtho';

// shaders / blending / rlgl bits
function LoadShaderFromMemory(vsCode, fsCode: PAnsiChar): TShader; cdecl; external 'raylib' name 'LoadShaderFromMemory';
procedure UnloadShader(shader: TShader); cdecl; external 'raylib' name 'UnloadShader';
function GetShaderLocation(shader: TShader; const uniformName: PAnsiChar): Integer; cdecl; external 'raylib' name 'GetShaderLocation';
procedure SetShaderValue(shader: TShader; locIndex: Integer; const value: Pointer; uniformType: Integer); cdecl; external 'raylib' name 'SetShaderValue';
procedure SetShaderValueMatrix(shader: TShader; locIndex: Integer; mat: TMatrix); cdecl; external 'raylib' name 'SetShaderValueMatrix';
procedure SetShaderValueTexture(shader: TShader; locIndex: Integer; texture: TTexture2D); cdecl; external 'raylib' name 'SetShaderValueTexture';
procedure BeginShaderMode(shader: TShader); cdecl; external 'raylib' name 'BeginShaderMode';
procedure EndShaderMode; cdecl; external 'raylib' name 'EndShaderMode';
procedure BeginBlendMode(mode: Integer); cdecl; external 'raylib' name 'BeginBlendMode';
procedure EndBlendMode; cdecl; external 'raylib' name 'EndBlendMode';
procedure rlDisableBackfaceCulling; cdecl; external 'raylib' name 'rlDisableBackfaceCulling';
procedure rlActiveTextureSlot(slot: Integer); cdecl; external 'raylib' name 'rlActiveTextureSlot';
procedure rlEnableTexture(id: LongWord); cdecl; external 'raylib' name 'rlEnableTexture';
procedure rlSetUniformSampler(locIndex: Integer; texUnit: LongWord); cdecl; external 'raylib' name 'rlSetUniformSampler';

// 3D shapes (immediate mode)
procedure DrawCube(position: TVector3; width, height, length: Single; color: TColor); cdecl; external 'raylib' name 'DrawCube';
procedure DrawCubeV(position, size: TVector3; color: TColor); cdecl; external 'raylib' name 'DrawCubeV';
procedure DrawCubeWiresV(position, size: TVector3; color: TColor); cdecl; external 'raylib' name 'DrawCubeWiresV';
procedure DrawSphere(centerPos: TVector3; radius: Single; color: TColor); cdecl; external 'raylib' name 'DrawSphere';
procedure DrawCylinder(position: TVector3; radiusTop, radiusBottom, height: Single; sides: Integer; color: TColor); cdecl; external 'raylib' name 'DrawCylinder';
procedure DrawPlane(centerPos: TVector3; size: TVector2; color: TColor); cdecl; external 'raylib' name 'DrawPlane';
procedure DrawGrid(slices: Integer; spacing: Single); cdecl; external 'raylib' name 'DrawGrid';
procedure DrawCircle3D(center: TVector3; radius: Single; rotationAxis: TVector3; rotationAngle: Single; color: TColor); cdecl; external 'raylib' name 'DrawCircle3D';
procedure DrawLine3D(startPos, endPos: TVector3; color: TColor); cdecl; external 'raylib' name 'DrawLine3D';
procedure DrawTriangle3D(v1, v2, v3: TVector3; color: TColor); cdecl; external 'raylib' name 'DrawTriangle3D';

// meshes / models / materials
procedure UploadMesh(var mesh: TMesh; isDynamic: Boolean); cdecl; external 'raylib' name 'UploadMesh';
function GenMeshCube(width, height, length: Single): TMesh; cdecl; external 'raylib' name 'GenMeshCube';
function GenMeshPlane(width, length: Single; resX, resZ: Integer): TMesh; cdecl; external 'raylib' name 'GenMeshPlane';
function GenMeshSphere(radius: Single; rings, slices: Integer): TMesh; cdecl; external 'raylib' name 'GenMeshSphere';
function GenMeshCylinder(radius, height: Single; slices: Integer): TMesh; cdecl; external 'raylib' name 'GenMeshCylinder';
function LoadModelFromMesh(mesh: TMesh): TModel; cdecl; external 'raylib' name 'LoadModelFromMesh';
procedure DrawModel(model: TModel; position: TVector3; scale: Single; tint: TColor); cdecl; external 'raylib' name 'DrawModel';
procedure DrawModelEx(model: TModel; position: TVector3; rotationAxis: TVector3; rotationAngle: Single; scale: TVector3; tint: TColor); cdecl; external 'raylib' name 'DrawModelEx';
procedure DrawMesh(mesh: TMesh; material: TMaterial; transform: TMatrix); cdecl; external 'raylib' name 'DrawMesh';
function LoadMaterialDefault: TMaterial; cdecl; external 'raylib' name 'LoadMaterialDefault';
procedure SetMaterialTexture(material: PMaterial; mapType: Integer; texture: TTexture2D); cdecl; external 'raylib' name 'SetMaterialTexture';
procedure DrawBillboard(camera: TCamera3D; texture: TTexture2D; position: TVector3; scale: Single; tint: TColor); cdecl; external 'raylib' name 'DrawBillboard';

// textures from files / images
function LoadImage(const fileName: PAnsiChar): TImage; cdecl; external 'raylib' name 'LoadImage';
function LoadTexture(const fileName: PAnsiChar): TTexture2D; cdecl; external 'raylib' name 'LoadTexture';
procedure SetTextureWrap(texture: TTexture2D; wrap: Integer); cdecl; external 'raylib' name 'SetTextureWrap';
procedure ImageDrawPixel(dst: PImage; posX, posY: Integer; color: TColor); cdecl; external 'raylib' name 'ImageDrawPixel';
function GetRayCollisionQuad(ray: TRay; p1, p2, p3, p4: TVector3): TRayCollision; cdecl; external 'raylib' name 'GetRayCollisionQuad';

implementation
end.
