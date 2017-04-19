{
Parameters are:
1 - local folder path
2 - FTP URL with port and remote folder path
3 - FTP login
4 - FTP password
Example:
c:/foldersync ftp://server.com:21/var/www/server.com/folder/ root qwerty

If no commandline parameters then INI file will be used instead
}

program FTPSync;

{$APPTYPE CONSOLE}


uses
  SysUtils,
  inifiles,
  strutils,
  Logfile in 'Logfile.pas',
  uFTPSync in 'uFTPSync.pas';

var
  ini   : TInifile;
  syncer: TFTPSyncer;

begin
  try
    if paramstr(5) <> emptystr then
    begin
      syncer := TFTPSyncer.Create(paramstr(1), paramstr(2), paramstr(3), paramstr(4), paramstr(5));
      syncer.SyncLocalToFtp();
    end
    else
    begin
      ini := TInifile.Create(ExtractFilePath(GetModuleName(HInstance)) + ansireplacestr(ExtractFileName(paramstr(0)),
          '.exe', '.ini'));
      try
        syncer := TFTPSyncer.Create(
            ini.ReadString('ftpsync', 'localfolder', ''),
            ini.ReadString('ftpsync', 'ftpurl', ''),
            ini.ReadString('ftpsync', 'ftpfolder', ''),
            ini.ReadString('ftpsync', 'login', ''),
            ini.ReadString('ftpsync', 'password', '')
            );
        syncer.SyncLocalToFtp;
      finally
        freeandnil(ini);
      end;
    end;
    readln;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

end.
