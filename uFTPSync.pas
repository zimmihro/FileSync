unit uFTPSync;

interface

uses idFTP, classes, sysutils, iduri, Generics.Collections, Generics.Defaults, Windows,
  StrUtils, IdFTPList, IdAllFTPListParsers;

type
  TLocalFile = class;

  TFTPFile = class
  private
    FFileName   : string;
    FDescription: string;
    FPath       : string;
    FContent    : TMemoryStream;
    FSize       : Int64;
    FFileDate   : tdatetime;
  public
    property FileName   : string read FFileName write FFileName;
    property Description: string read FDescription write FDescription;
    property Path       : string read FPath write FPath;
    property Content    : TMemoryStream read FContent write FContent;
    property Size       : Int64 read FSize write FSize;
    property FileDate   : tdatetime read FFileDate write FFileDate;
    /// <summary>Constructor, bereitet TMemoryStream im Feld FContent vor</summary>
    constructor Create;
    /// <summary>Destructor, leert den TMemorystrem im Feld FContent</summary>
    destructor Destroy; override;
    /// <summary>gibt den komplette Pfad der Datei inklusive Dateinamen als String zurück</summary>
    function ToString: string; override;
  end;

  TFtpFileList = class(TObjectList<TFTPFile>)
  private
    RemoteFolderList: TStringList;
  public
    constructor Create; overload;
    /// <summary>liest die Dateien eine FTP-Verzeichnisses aus und speichert diese in eine Liste</summary>
    procedure ParseRemoteDirectory(FtpConnection: TIdFTP; RemoteFolder: string; FtpFileList: TFtpFileList);
    function SearchForFile(LocalFile: TLocalFile): boolean;
    function SerchForFolder(FolderName: string): boolean;
  end;

  TLocalFile = class
  private
    FFileName  : string;
    FPath      : string;
    FUnixPath  : string;
    FFileDate  : tdatetime;
    FSize      : Int64;
    FAttributes: integer;
    function getUnixPath(): string;
  public
    property FileName  : string read FFileName write FFileName;
    property Path      : string read FPath write FPath;
    property UnixPath  : string read getUnixPath write FUnixPath;
    property FileDate  : tdatetime read FFileDate write FFileDate;
    property Size      : Int64 read FSize write FSize;
    property Attributes: integer read FAttributes write FAttributes;
    procedure SendContent(FtpConnection: TIdFTP; folder: string);
  end;

  TLocalFileList = class(TObjectList<TLocalFile>)
  public
    constructor Create; overload;
    procedure ParseLocalDirectory(localPath: string; Result: TLocalFileList);
  end;

  TFTPSyncer = class
  private
    FFTPFiles     : TFtpFileList;
    FLocalFiles   : TLocalFileList;
    FFtpConnection: TIdFTP;
    FurlConnection: TIdURI;
    FLocalFolder  : string;
    FFtpUrl       : string;
    FFtpFolder    : string;
    FLogin        : string;
    FPassword     : string;
  public
    property FTPFileList     : TFtpFileList read FFTPFiles write FFTPFiles;
    property LocalFileList   : TLocalFileList read FLocalFiles write FLocalFiles;
    property FtpConnection: TIdFTP read FFtpConnection write FFtpConnection;
    property URLConnection: TIdURI read FurlConnection write FurlConnection;
    property LocalFolder  : string read FLocalFolder write FLocalFolder;
    property FtpUrl       : string read FFtpUrl write FFtpUrl;
    property FtpFolder    : string read FFtpFolder write FFtpFolder;
    property Login        : string read FLogin write FLogin;
    property Password     : string read FPassword write FPassword;
    constructor Create(LocalFolderInput, FtpUrlInput: string; FtpFolderInput: string; LoginInput, PasswordInput: string);
    procedure SyncLocalToFTP();
    procedure OpenFTPConnection();
  end;

implementation

/// <summary>Constructor, bereitet TMemoryStream im Feld FContent vor</summary>
constructor TFTPFile.Create;
begin
  self.Content := TMemoryStream.Create; // supports all encodings
end;

/// <summary>Destructor, leert den TMemorystrem im Feld FContent</summary>
destructor TFTPFile.Destroy;
begin
  Content := nil;
  inherited;
end;

/// <summary>gibt den komplette Pfad der Datei inklusive Dateinamen als String zurück</summary>
function TFTPFile.ToString: string;
begin
  if (self.Path <> '') and not EndsStr('/', self.Path) then
    self.Path := self.Path + '/';
  Result := self.Path + self.FileName;
end;

constructor TFtpFileList.Create;
begin
  inherited Create;
  OwnsObjects := True;
  self.RemoteFolderList := TStringList.Create;
end;

procedure TFtpFileList.ParseRemoteDirectory(FtpConnection: TIdFTP; RemoteFolder: string; FtpFileList: TFtpFileList);

  procedure ParseDirectory(const RemoteFolder: string);
  var
    remoteFile       : TFTPFile;
    i                : integer;
    delimiterlocation: integer;
    Name             : string;
    folder           : string;
    RemoteFolderList : TStringList;
  begin
    try
      RemoteFolderList := TStringList.Create;
      FtpConnection.ChangeDir(RemoteFolder);
      FtpConnection.List(RemoteFolderList);
      for i := 0 to RemoteFolderList.Count - 1 do
      begin
        folder := RemoteFolderList[i];
        delimiterlocation := LastDelimiter(':', folder) + 3;
        if delimiterlocation > 0 then
          name := copy(folder, delimiterlocation + 1, length(folder) - delimiterlocation)
        else
          name := folder;
        if folder[1] = 'd' then
          ParseDirectory(RemoteFolder + '/' + name)
        else
        begin
          remoteFile := TFTPFile.Create;
          try
            remoteFile.FileName := name;
            remoteFile.Description := folder;
            remoteFile.Path := RemoteFolder;
            remoteFile.Size := FtpConnection.Size(name);
            remoteFile.FileDate := FtpConnection.FileDate(name);
            FtpFileList.add(remoteFile);
          except
            FreeAndNil(remoteFile);
            raise;
          end;
        end;
      end;
    finally
      FreeAndNil(RemoteFolderList);
    end;
    if RemoteFolder <> '' then
      FtpConnection.ChangeDirUp;
  end;

begin
  if not FtpConnection.Connected then
    Exit;
  Clear;
  ParseDirectory(RemoteFolder);
end;

/// <summary>Überprüft ob eine lokale Datei auf dem FTP-Server vorhanden ist</summary>
/// @param LocalFile = TLocalFile-Object mit den erforderlichen Daten zum Abgleich
/// @return = True bei Vorhandensein, sonst False
function TFtpFileList.SearchForFile(LocalFile: TLocalFile): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to self.Count - 1 do
  begin
    if (self[i].FileName = LocalFile.FileName) and (self[i].Size = LocalFile.Size) and
        (self[i].FileDate >= LocalFile.FileDate) and self[i].Path.EndsWith(LocalFile.UnixPath) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TFtpFileList.SerchForFolder(FolderName: string): boolean;
var
  i: integer;
begin
  Result := False;
  for i := 0 to self.RemoteFolderList.Count - 1 do
  begin
    if RemoteFolderList[i].Contains(FolderName) then
      Result := True;
  end;
end;

constructor TFTPSyncer.Create(LocalFolderInput, FtpUrlInput: string; FtpFolderInput: string; LoginInput, PasswordInput: string);
begin
  self.FTPFileList := TFtpFileList.Create;
  self.LocalFileList := TLocalFileList.Create;
  self.LocalFolder := LocalFolderInput;
  self.FtpUrl := FtpUrlInput;
  self.FtpFolder := FtpFolderInput;
  self.Login := LoginInput;
  self.Password := PasswordInput;
end;

procedure TFTPSyncer.OpenFTPConnection;
begin
  self.FtpConnection := TIdFTP.Create(nil);
  self.URLConnection := TIdURI.Create(self.FtpUrl);
  self.FtpConnection.Host := self.URLConnection.Host;
  self.FtpConnection.port := strtointdef(self.URLConnection.port, 21);
  self.FtpConnection.UserName := self.Login;
  self.FtpConnection.Password := self.Password;
  self.FtpConnection.AutoLogin := True;
  self.FtpConnection.Passive := True;
  writeln('Stelle Verbindung her zu: ' + self.Login + ':' + self.Password + '@' + self.FtpUrl);
  self.FtpConnection.Connect;
end;

procedure TFTPSyncer.SyncLocalToFTP();
var
  i: integer;
begin
  try
    self.OpenFTPConnection;
    self.FTPFileList.ParseRemoteDirectory(self.FtpConnection, self.FtpFolder, self.FTPFileList);
    self.LocalFileList.ParseLocalDirectory(self.LocalFolder, self.LocalFileList);
    for i := 0 to self.LocalFileList.Count - 1 do
    begin
      if not self.FTPFileList.SearchForFile(LocalFileList[i]) then
      begin
        writeln('fehlende Datei ermittelt: ' + self.LocalFileList[i].Path + '\' + self.LocalFileList[i].FileName);
        self.LocalFileList[i].SendContent(self.FtpConnection, self.LocalFileList[i].Path);
      end;
    end;
    writeln('Abgleich abgeschloßen');
  finally

  end;
end;

{ TLocalFile }

/// <summary>Wandelt Windows-Pfade in Unix-Pfade um (einfacher Austausch von '\' zu'/')</summary>
/// @return = String mit einem gültigen Unix-Pfad
function TLocalFile.getUnixPath: string;
begin
  Result := self.FPath.Replace('\', '/', [rfReplaceAll]);
end;

procedure TLocalFile.SendContent(FtpConnection: TIdFTP; folder: string);
var
  filestream      : TMemoryStream;
  workingDirectory: string;
begin
  if FtpConnection.Connected then
  begin
    workingDirectory := FtpConnection.RetrieveCurrentDir;
    filestream := TMemoryStream.Create;
    filestream.LoadFromFile(self.Path + '\' + self.FileName);
    try
      FtpConnection.ChangeDir(folder.Replace('\', '/', [rfReplaceAll]));
    except
      on E: Exception do
      begin
        FtpConnection.MakeDir(folder.Replace('\', '/', [rfReplaceAll]));
        FtpConnection.ChangeDir(folder.Replace('\', '/', [rfReplaceAll]));
      end;
    end;
    FtpConnection.Put(filestream, self.FileName, False);
    FtpConnection.ChangeDir(workingDirectory);
    filestream.Free
  end;
end;

{ TLocalFilesList }

constructor TLocalFileList.Create;
begin
  inherited Create;
  OwnsObjects := True;
end;

procedure TLocalFileList.ParseLocalDirectory(localPath: string; Result: TLocalFileList);
var
  Path     : string;
  rec      : TSearchRec;
  LocalFile: TLocalFile;
begin
  Path := IncludeTrailingPathDelimiter(localPath);
  if FindFirst(ExtractFilePath(ParamStr(0)) + Path + '*.*', faDirectory, rec) = 0 then
    try
      repeat
        if (rec.Name <> '.') and (rec.Name <> '..') then
        begin
          if rec.Attr <> faDirectory then
          begin
            try
              LocalFile := TLocalFile.Create;
              LocalFile.FileName := rec.Name;
              LocalFile.Path := localPath;
              LocalFile.FileDate := rec.TimeStamp;
              LocalFile.Size := rec.Size;
              Result.add(LocalFile);
            except
              FreeAndNil(LocalFile);
              raise;
            end;
          end;
          self.ParseLocalDirectory(Path + rec.Name, Result);
        end;
      until FindNext(rec) <> 0;
    finally
      sysutils.FindClose(rec);
    end;
end;

end.
