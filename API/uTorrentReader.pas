///
///  Author: Laurent Meyer
///  Contact: qBit4Delphi@ea4d.com
///  Version: 2.0.0
///
///  https://github.com/bnzbnz/qBit4Delphi
///  https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1)
///  https://www.nayuki.io/page/bittorrent-bencode-format-tools
///

unit uTorrentReader;
interface
uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults,
  uBEncode, DateUtils, SysUtils;

const
  TORRENTREADER_PATH_SEPARATOR = '\';

type
  TTorrentReaderOptions = set of (
    trRaiseException,    // Will raise Exception on error (Default), silent otherwise
    trHybridAsV1,        // Handle hybrid torrent files as V1 (Default)
    trHybridAsV2         // Handle hybrid torrent files as V2
  );

  TFileData = class(TObject)
    FullPath: string;
    Length: Int64;
    PathList: TStringList;
    PiecesRoot: AnsiString; // V2 Only
    PiecesCount: Int64; // V2 Only
    constructor Create; overload;
    destructor Destroy; override;
  end;

  TTorrentDataInfo = class(TObject)
    FileList: TObjectList<TFileData>;
    FilesSize: Int64;
    HasMultipleFiles: Boolean;
    IsHybrid: Boolean;
    IsPrivate: Boolean;
    Length: Int64;
    MetaVersion: Int64;
    Name: string;
    Pieces: AnsiString; // V1 Only
    PiecesCount: Int64; // V1 Only;
    PieceLength: Int64;
    constructor Create; overload;
    destructor Destroy; override;
  end;

  TTorrentData = class(TObject)
  public
    Announce: string;
    AnnouncesDict : TDictionary<Integer, TStringList>;
    Comment: TStringList;
    CreatedBy: string;
    CreationDate: TDateTime;
    HashV1: string;
    HashV2: string;
    Info: TTorrentDataInfo;
    WebSeeds: TStringList;
    constructor Create; overload;
    destructor Destroy; override;
  end;

  TTorrentReader = class(TObject)
  private
    FBe: TBEncoded;
    FData: TTorrentData;
    function GetSHA1(Enc: TBEncoded): string;
    function GetSHA2(Enc: TBEncoded): string;
    procedure Parse(Be: TBEncoded; Options: TTorrentReaderOptions);
  public
    class function LoadFromBufferPtr(BufferPtr: PAnsiChar; Options: TTorrentReaderOptions = [trRaiseException, trHybridAsV2]): TTorrentReader;
    class function LoadFromMemoryStream(MemStream: TMemoryStream; Options: TTorrentReaderOptions = [trRaiseException, trHybridAsV2]): TTorrentReader;
    class function LoadFromFile(Filename: string; Options: TTorrentReaderOptions = [trRaiseException, trHybridAsV2]): TTorrentReader;
    constructor Create; overload;
    destructor Destroy; override;
    property BEncoded: TBEncoded read FBe;
    property Data: TTorrentData read FData;
  end;

implementation
{$IF defined(MSWINDOWS)}
uses Windows;
{$ELSE}
uses System.Types, System.Hash;
{$ENDIF}

{$IF defined(MSWINDOWS)}
function CryptAcquireContextA(var phProv: ULONG_PTR; pszContainer: LPCSTR; pszProvider: LPCSTR; dwProvType: DWORD; dwFlags: DWORD): BOOL; stdcall;
  external 'advapi32.dll' Name 'CryptAcquireContextA';
function CryptReleaseContext(hProv: ULONG_PTR; dwFlags: ULONG_PTR): BOOL; stdcall;
  external 'advapi32.dll' Name 'CryptReleaseContext';
function CryptCreateHash(hProv: ULONG_PTR; Algid: DWORD; hKey: ULONG_PTR; dwFlags: DWORD; var phHash: ULONG_PTR): BOOL; stdcall;
  external 'advapi32.dll' Name 'CryptCreateHash';
function CryptGetHashParam(hHash: ULONG_PTR; dwParam: DWORD; pbData: LPBYTE; var pdwDataLen: DWORD; dwFlags: DWORD): BOOL; stdcall;
  external 'advapi32.dll' Name 'CryptGetHashParam';
function CryptHashData(hHash: ULONG_PTR; pbData: LPBYTE; dwDataLen, dwFlags: DWORD): BOOL; stdcall;
  external 'advapi32.dll' Name 'CryptHashData';
function CryptDeriveKey(hProv: ULONG_PTR; Algid: DWORD; hBaseData: ULONG_PTR; dwFlags: DWORD; var phKey: ULONG_PTR): BOOL;
  external 'advapi32.dll' Name 'CryptDeriveKey';
function CryptDestroyHash(hHash: ULONG_PTR): BOOL; stdcall;
  external 'advapi32.dll' Name 'CryptDestroyHash';
function CryptDestroyKey(hKey: ULONG_PTR): BOOL; stdcall;
  external 'advapi32.dll' Name 'CryptDestroyKey';

// AlgoID : SHA1 = $8004, SHA2-256 = $800C
function WinCryptSHA(AlgoID: DWORD; Buffer: Pointer; Size: DWORD): AnsiString;
var
  phProv: ULONG_PTR ;
  phHash: ULONG_PTR ;
  ByteBuffer: Array[0..31] of Byte;
  Len: DWORD;
begin
  CryptAcquireContextA(phProv, nil, nil, 24, DWORD($F0000000));
  CryptCreateHash(phProv, AlgoID, 0, 0, phHash);
  CryptHashData(phHash, LPBYTE(Buffer), Size,0);
  Len := Length(ByteBuffer);
  CryptGetHashParam(phHash, 2, @ByteBuffer, Len, 0);
  SetLength(Result, Len * 2);
  BinToHex(@ByteBuffer, PAnsiChar(@Result[1]), Len);
  CryptDestroyHash(phHash);
  CryptReleaseContext(phProv, 0);
end;
{$ENDIF}

procedure RaiseException(Str: string);
begin
  raise Exception.Create('TTorrentReader: ' + Str);
end;

{ TTorrentData }

constructor TTorrentData.Create;
begin
  inherited;
  Info := TTorrentDataInfo.Create;
  AnnouncesDict := TDictionary<Integer, TStringList>.Create;
  WebSeeds := TStringList.Create;
  Comment := TStringList.Create;
  Comment.StrictDelimiter := True;
  Comment.Delimiter := #$A;
end;

destructor TTorrentData.Destroy;
begin
  Comment.Free;
  WebSeeds.Free;
  for var Tier in AnnouncesDict do Tier.Value.Free;
  AnnouncesDict.Free;
  Info.Free;
  inherited;
end;

{ TTorrentReader }

constructor TTorrentReader.Create;
begin
  inherited;
  FBe := nil;
  FData := TTorrentData.Create;
end;

destructor TTorrentReader.Destroy;
begin
  FBe.Free;
  FData.Free;
  inherited;
end;

function TTorrentReader.GetSHA1(Enc: TBEncoded): string;
begin
{$IF defined(MSWINDOWS)}
  Result := LowerCase(string(WinCryptSHA($8004, Pointer(Enc.BufferStart), Enc.BufferEnd - Enc.BufferStart)));
{$ELSE}
  var SHA := THashSHA1.Create;
  SHA.Update( PByte(Enc.BufferStart)^ , Enc.BufferEnd - Enc.BufferStart);
  Result := SHA.HashAsString;
{$ENDIF}
end;

function TTorrentReader.GetSHA2(Enc: TBEncoded): string;
begin
{$IF defined(MSWINDOWS)}
  Result := LowerCase(string(WinCryptSHA($800C, Pointer(Enc.BufferStart), Enc.BufferEnd - Enc.BufferStart)));
{$ELSE}
  var SHA := THashSHA2.Create;
  SHA.Update( PByte(Enc.BufferStart)^ , Enc.BufferEnd - Enc.BufferStart);
  Result := SHA.HashAsString;
{$ENDIF}
end;

class function TTorrentReader.LoadFromBufferPtr(BufferPtr: PAnsiChar; Options: TTorrentReaderOptions = [trRaiseException, trHybridAsV2]): TTorrentReader;
begin
  Result := nil;
  try
    Result := TTorrentReader.Create;
    Result.FBe := TBEncoded.Create(BufferPtr);
    Result.Parse(Result.FBe, Options);
  except
    on E : Exception do
    begin
      FreeAndNil(Result);
      if trRaiseException in Options then raise;
    end;
  end;
end;

class function TTorrentReader.LoadFromMemoryStream(MemStream: TMemoryStream; Options: TTorrentReaderOptions = [trRaiseException, trHybridAsV2]): TTorrentReader;
begin
  var BufferPtr := PAnsiChar(MemStream.Memory);
  Result := LoadFromBufferPtr(BufferPtr, Options);
end;

class function TTorrentReader.LoadFromFile(Filename: string; Options: TTorrentReaderOptions = [trRaiseException, trHybridAsV2]): TTorrentReader;
var
  MemStream: TMemoryStream;
begin
  MemStream := nil;
  try
    MemStream := TMemoryStream.Create;
    MemStream.LoadFromFile(Filename);
    Result := LoadFromMemoryStream(MemStream, Options);
  finally
    MemStream.Free;
  end;
end;

procedure TTorrentReader.Parse(Be: TBEncoded; Options: TTorrentReaderOptions);

  procedure ParseFileListV2(Dic: TBEncoded; const Path: string; FileData: TFileData);
  begin
    if not assigned(Dic.ListData) then exit;
    for var i := 0 to Dic.ListData.Count - 1 do
    begin
      var TmpDic := Dic.ListData.Items[i];
      var Hdr := TmpDic.Header;
      var Str := TmpDic.Data.StringData;
      var Int := TmpDic.Data.IntegerData;
      if (Hdr = '') and (Str = '') then
      begin
        FileData := TFileData.Create;
        FData.Info.FileList.Add(FileData);
        FileData.FullPath := Path;
        FileData.PathList.Delimiter := TORRENTREADER_PATH_SEPARATOR;
        FileData.PathList.QuoteChar := #0;
        FileData.PathList.StrictDelimiter := True;
        FileData.PathList.DelimitedText := string(Path);
      end
      else if assigned(FileData) then
      begin
       if Hdr = 'length' then FileData.Length := Int;
       if Hdr = 'pieces root' then
       begin
        FileData.PiecesRoot := Str;
        FileData.PiecesCount := Length(Str) div 32;
       end;
      end;
      if assigned(TmpDic.data.ListData) then
        if Path <> '' then
          ParseFileListV2(TmpDic.Data, Path + TORRENTREADER_PATH_SEPARATOR + UTF8ToString(Hdr),  FileData)
        else
          ParseFileListV2(TmpDic.Data, UTF8ToString(Hdr),  FileData);
    end;
  end;

var
  Enc, Info: TBEncoded;
  EncStr: string;
  SList: TStringList;

begin
  Info := Be.ListData.FindElement('info'); //Helper;
  try
    //MetaVersion
    FData.Info.MetaVersion := 1;
    Enc := Info.ListData.FindElement('meta version');
    if assigned(Enc) then FData.Info.MetaVersion:= Enc.IntegerData;
    if FData.Info.MetaVersion >2 then RaiseException('Unknown Format : ' +  FData.Info.MetaVersion.ToString);

    // IsHybrid
    FData.Info.IsHybrid := (Info.ListData.FindElement('files') <> nil)
                            and (Info.ListData.FindElement('file tree') <> nil);

    if (FData.Info.IsHybrid) and (trHybridAsV1 in Options) then FData.Info.MetaVersion := 1;
    if (FData.Info.IsHybrid) and (trHybridAsV2 in Options) then FData.Info.MetaVersion := 2;

    //Announce
    Enc := Be.ListData.FindElement('announce');
    if assigned(Enc) then FData.Announce := UTF8ToString(Enc.StringData);

    // AnnounceList : http://bittorrent.org/beps/bep_0012.html
    var AnnounceList := Be.ListData.FindElement('announce-list') as TBEncoded;
    if assigned(AnnounceList) then
    begin
      for var SubA := 0 to AnnounceList.ListData.Count - 1 do
        case AnnounceList.ListData[SubA].Data.Format of
          befList: // Multi Tiers
            begin
              if not FData.AnnouncesDict.TryGetValue( FData.AnnouncesDict.Count , SList) then
              begin
                SList := TStringList.Create;
                FData.AnnouncesDict.Add(FData.AnnouncesDict.Count, SList);
              end;
              for var SubL := 0 to  AnnounceList.ListData[SubA].Data.ListData.Count - 1 do
                SList.AddObject(UTF8ToString(AnnounceList.ListData[SubA].Data.ListData[SubL].Data.StringData), Pointer(FData.AnnouncesDict.Count - 1));
            end;
          befString: // Single Tier
            begin
              if not FData.AnnouncesDict.TryGetValue( 0, SList) then
              begin
                SList := TStringList.Create;
                FData.AnnouncesDict.Add(0, SList);
              end;
              SList.AddObject(UTF8ToString((AnnounceList.ListData[SubA].Data).StringData), Pointer(0));
            end;
        end;
    end;

    // Comment
    Enc := Be.ListData.FindElement('comment');
    if assigned(Enc) then FData.Comment.DelimitedText := UTF8ToString(Enc.StringData);

    // CreatedBy
    Enc := Be.ListData.FindElement('created by');
    if assigned(Enc) then FData.CreatedBy := UTF8ToString(Enc.StringData);

    // CreationDate
    Enc := Be.ListData.FindElement('creation date');
    if assigned(Enc) then FData.CreationDate := TTimeZone.Local.ToLocalTime(UnixToDateTime(Enc.IntegerData));

    // Hash
    if (FData.Info.MetaVersion = 1) or (FData.Info.IsHybrid) then FData.HashV1 := GetSHA1(Info);
    if (FData.Info.MetaVersion = 2) or (FData.Info.IsHybrid) then FData.HashV2 := GetSHA2(Info);

    // Name:
    Enc := Info.ListData.FindElement('name') as TBEncoded;
    if assigned(Enc) then FData.Info.Name := UTF8ToString(Enc.StringData);

    // Length:
    Enc := Info.ListData.FindElement('length') as TBEncoded;
    if assigned(Enc) then FData.Info.Length := Enc.IntegerData;

    // PieceLength:
    Enc := Info.ListData.FindElement('piece length') as TBEncoded;
    if assigned(Enc) then FData.Info.PieceLength := Enc.IntegerData;

    // Pieces:
    Enc := Info.ListData.FindElement('pieces') as TBEncoded;
    if assigned(Enc) then
    begin
      FData.Info.Pieces := Enc.StringData;
      FData.Info.PiecesCount := Length(FData.Info.Pieces) div 20;
    end;

    //Private
    FData.Info.IsPrivate := False;
    Enc := Info.ListData.FindElement('private') as TBEncoded;
    if assigned(Enc) then FData.Info.IsPrivate := Enc.IntegerData = 1;

    //UrlList:
    Enc := Be.ListData.FindElement('url-list') as TBEncoded;
    if assigned(Enc) then
      if Enc.ListData = nil then
        FData.WebSeeds.Add(String(Enc.StringData))
      else
        for var i := 0 to Enc.ListData.Count - 1 do
          FData.WebSeeds.Add(UTF8ToString(Enc.ListData[i].Data.StringData));

    // files :
    if FData.Info.MetaVersion = 1 then
    begin // V1
      var FL := Info.ListData.FindElement('files');
      if FL <> nil then
      for var i := 0 to FL.ListData.Count - 1 do
      begin
        // Multiple Files/Folders
        var FileData := TFileData.Create;
        var FLD := FL.ListData.Items[i].Data;
        FileData.Length := FLD.ListData.FindElement('length').IntegerData;
        var FLDP := FLD.ListData.FindElement('path');
        for var j := 0 to FLDP.ListData.Count - 1 do
          FileData.PathList.Add(UTF8ToString(FLDP.ListData.Items[j].Data.StringData));
        FileData.PathList.Delimiter := TORRENTREADER_PATH_SEPARATOR;
        FileData.PathList.QuoteChar := #0;
        FileData.PathList.StrictDelimiter := True;
        FileData.FullPath := FileData.PathList.DelimitedText;
        FData.Info.FileList.Add(FileData);
      end else begin
        // A Single File
        var FileData := TFileData.Create;
        FileData.Length := FData.Info.Length;
        FileData.FullPath := FData.Info.Name;
        FileData.PathList.Add(FData.Info.Name);
        FData.Info.FileList.Add(FileData);
      end;
    end else // V2
      ParseFileListV2(Info.ListData.FindElement('file tree'), EncStr, nil);

    // **************** Helpers **************** //

    // HasMultipleFiles
    FData.Info.HasMultipleFiles := True;
    if FData.Info.FileList.Count = 1  then
      if  FData.Info.Name =  FData.Info.FileList[0].FullPath then
      begin
        FData.Info.Name := '';
        FData.Info.HasMultipleFiles := False;
      end;

    // FilesSize & PiecesCount
    Data.Info.FilesSize := 0;
    for var fle in Data.Info.FileList do
    begin
      Data.Info.FilesSize := Data.Info.FilesSize + fle.Length;
      if Data.Info.MetaVersion > 1 then
        Data.Info.PiecesCount := Data.Info.PiecesCount + fle.PiecesCount;
    end;
  except
    RaiseException('Invalid Torrent File');
  end;
end;

{ TTorrentDataInfo }

constructor TTorrentDataInfo.Create;
begin
  inherited;
  FileList := TObjectList<TFileData>.Create(True);
end;

destructor TTorrentDataInfo.Destroy;
begin
  FileList.Free;
  inherited;
end;

{ TFileData }

constructor TFileData.Create;
begin
  inherited;
  PathList := TStringList.Create;
end;

destructor TFileData.Destroy;
begin
  PathList.Free;
  inherited;
end;

end.
