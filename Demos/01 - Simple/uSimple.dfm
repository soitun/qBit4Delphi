object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Simple'
  ClientHeight = 342
  ClientWidth = 635
  Color = clBtnFace
  DefaultMonitor = dmMainForm
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  FormStyle = fsStayOnTop
  Position = poScreenCenter
  OnClose = FormClose
  OnShow = FormShow
  TextHeight = 13
  object LBTorrents: TListBox
    Left = 0
    Top = 0
    Width = 635
    Height = 342
    Align = alClient
    ItemHeight = 13
    TabOrder = 1
    ExplicitHeight = 299
  end
  object Warning: TMemo
    Left = 8
    Top = 8
    Width = 619
    Height = 326
    Lines.Strings = (
      
        'WARNING... WARNING... WARNING... (this is said) : THIS A WORK IN' +
        ' PROGRESS'
      ''
      
        'In order to build and use qBit4Delphi some Embarcadero units nee' +
        'd to be patched (Fixes and Enhancements)'
      
        'This version is tested and patched against Delphi 10.4.2 (Sydney' +
        '/Community Edition) and Delphi 11 (Alexandria) :'
      ''
      'TO DO SO EXECUTE : Patcher.exe in the main directory'
      'The patched units will be located in JSON/21 and/or JSON/22'
      'Please add these units in you project :'
      ''
      '  {$IFDEF VER340}'
      '    REST.Json.Types in '#39'..\..\API\JSON\21\REST.Json.Types.pas'#39','
      
        '    REST.JsonReflect in '#39'..\..\API\JSON\21\REST.JsonReflect.pas'#39 +
        ','
      '    System.JSON in '#39'..\..\API\JSON\21\System.JSON.pas'#39','
      '    REST.Json in '#39'..\..\API\JSON\21\REST.Json.pas'#39','
      '  {$ENDIF }'
      '  {$IFDEF VER350}'
      '    REST.Json.Types in '#39'..\..\API\JSON\22\REST.Json.Types.pas'#39','
      
        '    REST.JsonReflect in '#39'..\..\API\JSON\22\REST.JsonReflect.pas'#39 +
        ','
      '    System.JSON in '#39'..\..\API\JSON\22\System.JSON.pas'#39','
      '    REST.Json in '#39'..\..\API\JSON\22\REST.Json.pas'#39','
      '  {$ENDIF}'
      ''
      'Any questions : qBit4Delphi@ea4d.com'
      'Laurent Meyer.')
    TabOrder = 0
  end
  object Timer1: TTimer
    Enabled = False
    OnTimer = Timer1Timer
    Left = 520
    Top = 112
  end
end
