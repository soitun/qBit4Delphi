///
///  Authors: ShareNET Networks, Laurent Meyer
///  Contact: qBit4Delphi@ea4d.com
///  Version: 2.0.1
///
///  https://github.com/bnzbnz/qBit4Delphi
///  https://torry.net/pages.php?id=650
///  https://stackoverflow.com/questions/34157958/delphi-how-to-use-bencode-to-get-info-hash
///

unit uBEncode;

interface

uses
  Classes, Contnrs, SysUtils;

type

  TBEncoded = class;
  TBEncodedFormat = (befEmpty, befString, befInteger, befList, befDictionary);
  TBEncodedData = class(TObject)
  public
    Header: AnsiString;
    Data: TBEncoded;
    constructor Create(Data: TBEncoded);
    destructor Destroy; override;
  end;

  TBEncodedDataList = class(TObjectList)
  protected
    function GetItems(Index: Integer): TBEncodedData;
    procedure SetItems(Index: Integer; AClass: TBEncodedData);
  public
    function FindElement(Header: AnsiString): TBEncoded;
    function Add(AClass: TBEncodedData): Integer;
    function Extract(Item: TBEncodedData): TBEncodedData;
    function Remove(AClass: TBEncodedData): Integer;
    function IndexOf(AClass: TBEncodedData): Integer;
    function First: TBEncodedData;
    function Last: TBEncodedData;
    procedure Insert(Index: Integer; AClass: TBEncodedData);
    property Items[Index: Integer]: TBEncodedData read GetItems write SetItems; default;
  end;

  TBEncoded = class(TObject)
  private
    FFormat: TBEncodedFormat;
    procedure SetFormat(Format: TBEncodedFormat);
  public
    StringData: AnsiString;
    IntegerData: int64;
    ListData: TBEncodedDataList;
    property Format: TBEncodedFormat read FFormat write SetFormat;
    class procedure Encode(Encoded: TBEncoded; var Output: TStringBuilder);
    destructor Destroy; override;
    constructor Create(Stream: TStream);
  end;

implementation
uses System.Types;

destructor TBEncodedData.Destroy;
begin
  Data.Free;
  inherited Destroy;
end;

constructor TBEncodedData.Create(Data: TBEncoded);
begin
  inherited Create;
  Self.Data := Data;
end;

destructor TBEncoded.Destroy;
begin
  if ListData <> nil then ListData.Free;
  inherited Destroy;
end;

constructor TBEncoded.Create(Stream: TStream);

  function GetString(Buffer: AnsiString): AnsiString;
  var
    X: AnsiChar;
  begin
    // loop until we come across it
    repeat
      if Stream.Read(X, 1) <> 1 then
        raise Exception.Create('');
      if not ((X in ['0'..'9']) or (x = ':')) then
        raise Exception.Create('');
      if X = ':' then
      begin
        if Buffer = '' then
          raise Exception.Create('');
        if Length(Buffer) > 8 then
          raise Exception.Create('');
        SetLength(Result, StrToInt(String(Buffer)));

        if Length(Result)>0 then
          if Stream.Read(Result[1], Length(Result)) <> Length(Result) then
            raise Exception.Create('');
        Break;
      end
      else
        Buffer := Buffer + X;
    until False;
  end;

var
  X: AnsiChar;
  Buffer: AnsiString;
  Data: TBEncodedData;
  Encoded: TBEncoded;
begin
  inherited Create;

  // get first character to determine the format of the proceeding data
  if Stream.Read(X, 1) <> 1 then
    raise Exception.Create('');

  // is it an integer?
  if X = 'i' then
  begin
    // yes it is, let's read until we come across e
    Buffer := '';
    repeat
      if Stream.Read(X, 1) <> 1 then
        raise Exception.Create('');
      if not ((X in ['0'..'9']) or (X = 'e')) then
        raise Exception.Create('');
      if X = 'e' then
      begin
        if Buffer = '' then
          raise Exception.Create('')
        else
        begin
          Format := befInteger;
          IntegerData := StrToInt64(String(Buffer));
          Break;
        end;
      end
      else
        Buffer := Buffer + X;
    until False;
  end
  // is it a list?
  else if X = 'l' then
  begin
    // its a list
    Format := befList;

    // loop until we come across e
    repeat
      // have a peek around and see if theres an e
      if Stream.Read(X, 1) <> 1 then
        raise Exception.Create('');
      // is it an e?
      if X = 'e' then
        Break;
      // otherwise move the cursor back
      Stream.Seek(-1, soFromCurrent);
      // create the element
      Encoded := TBEncoded.Create(Stream);
      // add it to the list
      ListData.Add(TBEncodedData.Create(Encoded));
    until False;
  end
  // is it a dictionary?
  else if X = 'd' then
  begin
    // its a dictionary :>
    Format := befDictionary;

    // loop until we come across e
    repeat
      // have a peek around and see if theres an e
      if Stream.Read(X, 1) <> 1 then
        raise Exception.Create('');
      // is it an e?
      if X = 'e' then
        Break;
      // if it isnt an e it has to be numerical!
      if not (X in ['0'..'9']) then
        raise Exception.Create('');
      // now read the string data
      Buffer := GetString(X);
      // create the element
      Encoded := TBEncoded.Create(Stream);
      // create the data element
      Data := TBEncodedData.Create(Encoded);
      Data.Header := Buffer;
      // add it to the list
      ListData.Add(Data);
    until False;
  end
  // is it a string?
  else if X in ['0'..'9'] then
  begin
    StringData := GetString(X);
    Format := befString;
  end
  else
    raise Exception.Create('');
end;

class procedure TBEncoded.Encode(Encoded: TBEncoded; var Output: TStringBuilder);
begin
  with Encoded do
  begin
    // what type of member is it?
    case Format of
      befString:
        begin
          Output.Append(Length(StringData));
          Output.Append(':');
          Output.Append(StringData);
        end;
      befInteger:
        begin
          Output.Append('i');
          Output.Append(IntegerData);
          Output.Append('e');
        end;
      befList:
      begin
        Output.Append('l');
        for var i := 0 to ListData.Count - 1 do
          Encode(TBEncoded(ListData[i].Data), Output);
        Output.Append('e');
      end;
      befDictionary:
      begin
        Output.Append( 'd');
        for var i := 0 to ListData.Count - 1 do
        begin
          Output.Append(Length(ListData[i].Header));
          Output.Append(':');
          Output.Append(ListData[i].Header);
          Encode(TBEncoded(ListData[i].Data), Output);
        end;
        Output.Append( 'e');
      end;
    end;
  end;
end;

procedure TBEncoded.SetFormat(Format: TBEncodedFormat);
begin
  if Format in [befList, befDictionary] then ListData := TBEncodedDataList.Create;
  FFormat := Format;
end;

function TBEncodedDataList.FindElement(Header: AnsiString): TBEncoded;
begin
  Result := nil;
  for var i := 0 to Count - 1 do
    if LowerCase(String(Items[i].Header)) = LowerCase(String(Header)) then
    begin
      Result := Items[i].Data;
      Break;
    end;
end;

function TBEncodedDataList.Add(AClass: TBEncodedData): Integer;
begin
  Result := inherited Add(AClass);
end;

function TBEncodedDataList.Extract(Item: TBEncodedData): TBEncodedData;
begin
  Result := TBEncodedData(inherited Extract(Item));
end;

function TBEncodedDataList.First: TBEncodedData;
begin
  Result := TBEncodedData(inherited First);
end;

function TBEncodedDataList.GetItems(Index: Integer): TBEncodedData;
begin
  Result := TBEncodedData(inherited Items[Index]);
end;

function TBEncodedDataList.IndexOf(AClass: TBEncodedData): Integer;
begin
  Result := inherited IndexOf(AClass);
end;

procedure TBEncodedDataList.Insert(Index: Integer; AClass: TBEncodedData);
begin
  inherited Insert(Index, AClass);
end;

function TBEncodedDataList.Last: TBEncodedData;
begin
  Result := TBEncodedData(inherited First);
end;

function TBEncodedDataList.Remove(AClass: TBEncodedData): Integer;
begin
  Result := inherited Remove(AClass);
end;

procedure TBEncodedDataList.SetItems(Index: Integer; AClass: TBEncodedData);
begin
  inherited Items[Index] := AClass;
end;

end.
