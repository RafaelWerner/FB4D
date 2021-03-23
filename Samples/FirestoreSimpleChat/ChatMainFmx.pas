{******************************************************************************}
{                                                                              }
{  Delphi FB4D Library                                                         }
{  Copyright (c) 2018-2021 Christoph Schneider                                 }
{  Schneider Infosystems AG, Switzerland                                       }
{  https://github.com/SchneiderInfosystems/FB4D                                }
{                                                                              }
{******************************************************************************}
{                                                                              }
{  Licensed under the Apache License, Version 2.0 (the "License");             }
{  you may not use this file except in compliance with the License.            }
{  You may obtain a copy of the License at                                     }
{                                                                              }
{      http://www.apache.org/licenses/LICENSE-2.0                              }
{                                                                              }
{  Unless required by applicable law or agreed to in writing, software         }
{  distributed under the License is distributed on an "AS IS" BASIS,           }
{  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    }
{  See the License for the specific language governing permissions and         }
{  limitations under the License.                                              }
{                                                                              }
{******************************************************************************}

unit ChatMainFmx;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.ImageList, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Objects,
  FMX.Controls.Presentation, FMX.Edit, FMX.TabControl,FMX.ListView.Types,
  FMX.ListView.Appearances, FMX.ListView.Adapters.Base, FMX.Layouts,
  FMX.ListView, FMX.StdCtrls, FMX.MultiResBitmap, FMX.ImgList, FMX.TextLayout,
  FB4D.Interfaces, FB4D.Configuration, FB4D.SelfRegistrationFra;

type
  TfmxChatMain = class(TForm)
    TabControl: TTabControl;
    tabChat: TTabItem;
    tabLogin: TTabItem;
    edtKey: TEdit;
    Text2: TText;
    edtProjectID: TEdit;
    Text3: TText;
    lsvChat: TListView;
    layPushMessage: TLayout;
    edtMessage: TEdit;
    btnPushMessage: TButton;
    lblVersionInfo: TLabel;
    layUserInfo: TLayout;
    btnSignOut: TButton;
    lblUserInfo: TLabel;
    FraSelfRegistration: TFraSelfRegistration;
    txtUpdate: TText;
    txtError: TText;
    btnDeleteMessage: TButton;
    btnEditMessage: TButton;
    layFBConfig: TLayout;
    edtBucket: TEdit;
    Text1: TText;
    shpProfile: TCircle;
    ImageList: TImageList;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btnSignOutClick(Sender: TObject);
    procedure btnPushMessageClick(Sender: TObject);
    procedure edtMessageKeyUp(Sender: TObject; var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
    procedure lsvChatItemClick(const Sender: TObject;
      const AItem: TListViewItem);
    procedure btnEditMessageClick(Sender: TObject);
    procedure btnDeleteMessageClick(Sender: TObject);
    procedure FraSelfRegistrationbtnCheckEMailClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure lsvChatUpdateObjects(const Sender: TObject;
      const AItem: TListViewItem);
  private type
    TPendingProfile = class
      Items: TList<TListViewItem>;
      Stream: TStream;
      constructor Create(FirstItem: TListViewItem);
      destructor Destroy; override;
    end;
  private type
    TMsgType = (myMsg, foreignMsg);
  private
    fConfig: TFirebaseConfiguration;
    fUID: string;
    fUserName: string;
    fMyImgIndex: integer;
    fEditDocID: string;
    fPendingProfiles: TDictionary<string {UID}, TPendingProfile>;
    function GetAuth: IFirebaseAuthentication;
    function GetStorage: IFirebaseStorage;
    function GetSettingFilename: string;
    procedure SaveSettings;
    procedure OnTokenRefresh(TokenRefreshed: boolean);
    procedure OnUserLogin(const Info: string; User: IFirebaseUser);
    procedure StartChat;
    procedure WipeToTab(ActiveTab: TTabItem);
    procedure EnterEditMode(const DocPath: string);
    procedure ExitEditMode(ClearEditBox: boolean);
    function GetMsgTextName(MsgType: TMsgType): string;
    function GetDetailTextName(MsgType: TMsgType): string;
    function GetProfileImgName(MsgType: TMsgType): string;
    procedure OnAuthRevoked(TokenRenewPassed: boolean);
    procedure OnChangedColDocument(Document: IFirestoreDocument);
    procedure OnDeletedColDocument(const DeleteDocumentPath: string;
      TimeStamp: TDateTime);
    procedure OnListenerError(const RequestID, ErrMsg: string);
    procedure OnStopListening(Sender: TObject);
    function SearchItem(const DocId: string): TListViewItem;
    procedure OnDocWrite(const Info: string; Document: IFirestoreDocument);
    procedure OnDocWriteError(const RequestID, ErrMsg: string);
    procedure OnDocDelete(const RequestID: string; Response: IFirebaseResponse);
    procedure OnDocDeleteError(const RequestID, ErrMsg: string);
    function AddProfileImgToImageList(const UID: string; Img: TBitmap): integer;
    procedure DownloadProfileImgAndAddToImageList(const UID: string;
      Item: TListViewItem);
    procedure OnGetStorage(const ObjName: string; Obj: IStorageObject);
    procedure OnStorageDownload(const ObjName: string; Obj: IStorageObject);
  end;

var
  fmxChatMain: TfmxChatMain;

implementation

uses
  System.IniFiles, System.IOUtils, System.JSON, System.Math,
  FB4D.Helpers, FB4D.Firestore, FB4D.Document;

{$R *.fmx}

const
  cDocID = 'Chat';

// Install the following Firestore Rule:
// rules_version = '2';
// service cloud.firestore {
//   match /databases/{database}/documents {
//     match /Chat/{document=**} {
// 	    allow read, write: if request.auth != null;}}

{ TfmxChatMain }

procedure TfmxChatMain.FormCreate(Sender: TObject);
var
  IniFile: TIniFile;
  LastEMail: string;
  LastToken: string;
begin
  Caption := Caption + ' - ' + TFirebaseHelpers.GetPlatform +
    ' [' + TFirebaseConfiguration.GetLibVersionInfo + ']';
  IniFile := TIniFile.Create(GetSettingFilename);
  try
    edtKey.Text := IniFile.ReadString('FBProjectSettings', 'APIKey', '');
    edtProjectID.Text :=
      IniFile.ReadString('FBProjectSettings', 'ProjectID', '');
    edtBucket.Text := IniFile.ReadString('FBProjectSettings', 'Bucket', '');
    LastEMail := IniFile.ReadString('Authentication', 'User', '');
    LastToken := IniFile.ReadString('Authentication', 'Token', '');
  finally
    IniFile.Free;
  end;
  fPendingProfiles := TDictionary<string, TPendingProfile>.Create;
  TabControl.ActiveTab := tabLogin;
  FraSelfRegistration.InitializeAuthOnDemand(GetAuth, OnUserLogin, LastToken,
    LastEMail, true, false, true);
  FraSelfRegistration.RequestProfileImg(GetStorage);
  if edtProjectID.Text.IsEmpty then
    edtProjectID.SetFocus;
end;

procedure TfmxChatMain.FormDestroy(Sender: TObject);
begin
  fPendingProfiles.Free;
end;

procedure TfmxChatMain.FraSelfRegistrationbtnCheckEMailClick(Sender: TObject);
begin
  FraSelfRegistration.btnCheckEMailClick(Sender);
end;

procedure TfmxChatMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FreeAndNil(fConfig);
end;

procedure TfmxChatMain.SaveSettings;
var
  IniFile: TIniFile;
begin
  IniFile := TIniFile.Create(GetSettingFilename);
  try
    IniFile.WriteString('FBProjectSettings', 'APIKey', edtKey.Text);
    IniFile.WriteString('FBProjectSettings', 'ProjectID', edtProjectID.Text);
    IniFile.WriteString('FBProjectSettings', 'Bucket', edtBucket.Text);
    IniFile.WriteString('Authentication', 'User', FraSelfRegistration.GetEMail);
    if assigned(fConfig) and fConfig.Auth.Authenticated then
      IniFile.WriteString('Authentication', 'Token',
        fConfig.Auth.GetRefreshToken)
    else
      IniFile.DeleteKey('Authentication', 'Token');
  finally
    IniFile.Free;
  end;
end;

procedure TfmxChatMain.OnTokenRefresh(TokenRefreshed: boolean);
begin
  SaveSettings;
end;

function TfmxChatMain.GetAuth: IFirebaseAuthentication;
begin
  fConfig := TFirebaseConfiguration.Create(edtKey.Text, edtProjectID.Text);
  result := fConfig.Auth;
  result.InstallTokenRefreshNotification(OnTokenRefresh);
  edtKey.Enabled := false;
  edtProjectID.Enabled := false;
end;

function TfmxChatMain.GetStorage: IFirebaseStorage;
begin
  Assert(assigned(fConfig), 'FirebaseConfiguration not initialized');
  if not edtBucket.Text.IsEmpty then
    edtBucket.Enabled := false;
  fConfig.SetBucket(edtBucket.Text);
  result := fConfig.Storage;
end;

function TfmxChatMain.GetSettingFilename: string;
var
  FileName: string;
begin
  FileName := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  result := IncludeTrailingPathDelimiter(
{$IFDEF IOS}
    TPath.GetDocumentsPath
{$ELSE}
    TPath.GetHomePath
{$ENDIF}
    ) + FileName + TFirebaseHelpers.GetPlatform + '.ini';
end;

procedure TfmxChatMain.OnUserLogin(const Info: string; User: IFirebaseUser);
begin
  fUID := User.UID;
  fUserName := User.DisplayName;
  if assigned(FraSelfRegistration.ProfileImg) then
    shpProfile.Fill.Bitmap.Bitmap.Assign(FraSelfRegistration.ProfileImg);
  StartChat;
end;

procedure TfmxChatMain.btnSignOutClick(Sender: TObject);
begin
  fConfig.Database.StopListener;
  fConfig.Auth.SignOut;
  fUID := '';
  fUserName := '';
  FraSelfRegistration.StartEMailEntering;
  WipeToTab(tabLogin);
end;

procedure TfmxChatMain.WipeToTab(ActiveTab: TTabItem);
var
  c: integer;
begin
  if TabControl.ActiveTab <> ActiveTab then
  begin
    ActiveTab.Visible := true;
{$IFDEF ANDROID}
    TabControl.ActiveTab := ActiveTab;
{$ELSE}
    TabControl.GotoVisibleTab(ActiveTab.Index, TTabTransition.Slide,
      TTabTransitionDirection.Normal);
{$ENDIF}
    for c := 0 to TabControl.TabCount - 1 do
      TabControl.Tabs[c].Visible := TabControl.Tabs[c] = ActiveTab;
  end;
end;

procedure TfmxChatMain.StartChat;
begin
  lblUserInfo.Text := fUserName + ' logged in';
  fConfig.Database.SubscribeQuery(TStructuredQuery.CreateForCollection(cDocID).
    OrderBy('DateTime', odAscending),
    OnChangedColDocument, OnDeletedColDocument);
  fConfig.Database.StartListener(OnStopListening, OnListenerError, OnAuthRevoked);
  btnEditMessage.Visible := false;
  btnDeleteMessage.Visible := false;
  btnPushMessage.Visible := true;
  fEditDocID := '';
  fMyImgIndex := AddProfileImgToImageList(fUID, FraSelfRegistration.ProfileImg);
  WipeToTab(tabChat);
end;

function TfmxChatMain.SearchItem(const DocId: string): TListViewItem;
var
  c: integer;
begin
  result := nil;
  for c := 0 to lsvChat.ItemCount - 1 do
    if lsvChat.Items[c].Purpose = TListItemPurpose.None then
      if lsvChat.Items[c].TagString = DocId then
        exit(lsvChat.Items[c]);
end;

function TfmxChatMain.GetMsgTextName(MsgType: TMsgType): string;
begin
  if MsgType = myMsg then
    result := 'Text3'
  else
    result := 'Text5';
end;

function TfmxChatMain.GetDetailTextName(MsgType: TMsgType): string;
begin
  if MsgType = myMsg then
    result := 'Text4'
  else
    result := 'Text6';
end;

function TfmxChatMain.GetProfileImgName(MsgType: TMsgType): string;
begin
  if MsgType = myMsg then
    result := 'Image1'
  else
    result := 'Image2';
end;

procedure TfmxChatMain.OnChangedColDocument(Document: IFirestoreDocument);
var
  Item: TListViewItem;
  Edited: TDateTime;
  UID: string;
  DetailInfo: string;
  ImgInd: integer;
  MsgType, InvType: TMsgType;
begin
  Item := SearchItem(Document.DocumentName(true));
  lsvChat.BeginUpdate;
  try
    if not assigned(Item) then
    begin
      Item := lsvChat.Items.AddItem(lsvChat.ItemCount);
      Item.TagString := Document.DocumentName(true);
    end;
    Item.Text := Document.GetStringValueDef('Message', '?');
    DetailInfo := Document.GetStringValueDef('Sender', '?') + ' at ' +
      DateTimeToStr(TFirebaseHelpers.ConvertToLocalDateTime(
        Document.GetTimeStampValueDef('DateTime', now)));
    Edited := Document.GetTimeStampValueDef('Edited', 0);
    if Edited > 0 then
      DetailInfo := DetailInfo + ' (edited ' +
        DateTimeToStr(TFirebaseHelpers.ConvertToLocalDateTime(Edited)) + ')';
    UID := Document.GetStringValueDef('UID', '?');
    if UID = fUID then
    begin
      MsgType := myMsg;
      InvType := foreignMsg;
      ImgInd := fMyImgIndex;
    end else begin
      MsgType := foreignMsg;
      InvType := myMsg;
      ImgInd := ImageList.Source.IndexOf(UID);
      if ImgInd < 0 then
      begin
        DownloadProfileImgAndAddToImageList(UID, Item);
        ImgInd := 0; // set to default avatar
      end else
        dec(ImgInd);
    end;
    Item.Tag := ord(MsgType);
    Item.Data[GetMsgTextName(MsgType)] := Item.Text;
    Item.Data[GetDetailTextName(MsgType)] := DetailInfo;
    Item.Data[GetProfileImgName(MsgType)] := ImgInd;
    Item.Data[GetMsgTextName(InvType)] := ''; // After re-login with other
    Item.Data[GetDetailTextName(InvType)] := ''; // other user the former
    Item.Data[GetProfileImgName(InvType)] := -1; // MsgType must removed
  finally
    lsvChat.EndUpdate;
  end;
  lsvChat.Selected := Item;
  txtUpdate.Text := 'Last message written at ' +
    FormatDateTime('HH:NN:SS.ZZZ', Document.UpdateTime);
end;

procedure TfmxChatMain.lsvChatItemClick(const Sender: TObject;
  const AItem: TListViewItem);
begin
  if AItem.Tag = ord(myMsg) then
  begin
    edtMessage.Text := AItem.Text;
    EnterEditMode(AItem.TagString);
  end else
    ExitEditMode(not fEditDocID.IsEmpty);
end;

procedure TfmxChatMain.EnterEditMode(const DocPath: string);
begin
  fEditDocID := copy(DocPath, DocPath.LastDelimiter('/') + 2);
  btnEditMessage.Visible := true;
  btnDeleteMessage.Visible := true;
  btnPushMessage.Visible := false;
  btnEditMessage.Enabled := true;
  btnDeleteMessage.Enabled := true;
end;

procedure TfmxChatMain.ExitEditMode(ClearEditBox: boolean);
begin
  if ClearEditBox then
    edtMessage.Text := '';
  fEditDocID := '';
  btnEditMessage.Visible := false;
  btnDeleteMessage.Visible := false;
  btnPushMessage.Visible := true;
  btnPushMessage.Enabled := true;
end;

procedure TfmxChatMain.OnDeletedColDocument(const DeleteDocumentPath: string;
  TimeStamp: TDateTime);
var
  Item: TListViewItem;
begin
  Item := SearchItem(DeleteDocumentPath);
  if assigned(Item) then
    lsvChat.Items.Delete(Item.Index);
  lsvChat.Selected := nil;
  txtUpdate.Text := 'Last message deleted at ' +
    FormatDateTime('HH:NN:SS.ZZZ', TimeStamp);
end;

procedure TfmxChatMain.btnPushMessageClick(Sender: TObject);
var
  Doc: IFirestoreDocument;
begin
  Doc := TFirestoreDocument.Create(TFirebaseHelpers.CreateAutoID);
  Doc.AddOrUpdateField(TJSONObject.SetString('Message', edtMessage.Text));
  Doc.AddOrUpdateField(TJSONObject.SetString('Sender', fUserName));
  Doc.AddOrUpdateField(TJSONObject.SetString('UID', fUID));
  Doc.AddOrUpdateField(TJSONObject.SetTimeStamp('DateTime', now));
  {$IFDEF DEBUG}
  TFirebaseHelpers.Log('Doc: ' + Doc.AsJSON.ToJSON);
  {$ENDIF}
  fConfig.Database.InsertOrUpdateDocument([cDocID, Doc.DocumentName(false)],
    Doc, nil, OnDocWrite, OnDocWriteError);
  btnPushMessage.Enabled := false;
end;

procedure TfmxChatMain.btnEditMessageClick(Sender: TObject);
var
  Doc: IFirestoreDocument;
begin
  Assert(not fEditDocID.IsEmpty, 'No doc ID to patch');
  Doc := TFirestoreDocument.Create(fEditDocID);
  Doc.AddOrUpdateField(TJSONObject.SetString('Message', edtMessage.Text));
  Doc.AddOrUpdateField(TJSONObject.SetTimeStamp('Edited', now));
  fConfig.Database.PatchDocument([cDocID, fEditDocID], Doc,
    ['Message', 'Edited'], OnDocWrite, OnDocWriteError);
  btnEditMessage.Enabled := false;
  btnDeleteMessage.Enabled := false;
end;

procedure TfmxChatMain.btnDeleteMessageClick(Sender: TObject);
begin
  Assert(not fEditDocID.IsEmpty, 'No doc ID to patch');
  fConfig.Database.Delete([cDocID, fEditDocID], nil, OnDocDelete,
    OnDocDeleteError);
  btnEditMessage.Enabled := false;
  btnDeleteMessage.Enabled := false;
end;

procedure TfmxChatMain.edtMessageKeyUp(Sender: TObject; var Key: Word;
  var KeyChar: Char; Shift: TShiftState);
begin
  if Key = vkReturn then
    if fEditDocID.IsEmpty then
      btnPushMessageClick(Sender)
    else
      btnEditMessageClick(Sender);
end;

procedure TfmxChatMain.OnDocWriteError(const RequestID, ErrMsg: string);
begin
  if btnPushMessage.Visible then
  begin
    txtError.Text := 'Failure while write message: ' + ErrMsg;
    btnPushMessage.Enabled := true
  end else begin
    txtError.Text := 'Failure while update message: ' + ErrMsg;
    btnEditMessage.Enabled := true;
    btnDeleteMessage.Enabled := true;
  end;
end;

procedure TfmxChatMain.OnDocWrite(const Info: string;
  Document: IFirestoreDocument);
begin
  if btnPushMessage.Visible then
    txtUpdate.Text := 'Last message sent on ' +
      DateTimeToStr(Document.UpdateTime)
  else
    txtUpdate.Text := 'Last message update on ' +
      DateTimeToStr(Document.UpdateTime);
  {$IFDEF DEBUG}
  TFirebaseHelpers.Log('Written ID: ' + Document.DocumentName(false));
  {$ENDIF}
  ExitEditMode(true);
end;

procedure TfmxChatMain.OnDocDelete(const RequestID: string;
  Response: IFirebaseResponse);
begin
  txtUpdate.Text := 'Last message deleted on ' + DateTimeToStr(now);
  ExitEditMode(true);
end;

procedure TfmxChatMain.OnDocDeleteError(const RequestID, ErrMsg: string);
begin
  txtUpdate.Text := 'Failre while deleted message ' + ErrMsg;
end;

procedure TfmxChatMain.OnStopListening(Sender: TObject);
begin
  txtUpdate.Text := 'Chat listener stopped';
end;

procedure TfmxChatMain.OnAuthRevoked(TokenRenewPassed: boolean);
begin
  if TokenRenewPassed then
    txtUpdate.Text := 'Chat authorization renewed'
  else
    txtError.Text := 'Chat authorization renew failed';
end;

procedure TfmxChatMain.OnListenerError(const RequestID, ErrMsg: string);
begin
  txtError.Text := 'Error in listener: ' + ErrMsg;
end;

procedure TfmxChatMain.lsvChatUpdateObjects(const Sender: TObject;
  const AItem: TListViewItem);

  function CalcHeight(MsgText: TListItemText; const Text: string): Integer;
  const
    cMinItemHeight = 60;
  var
    Layout: TTextLayout;
  begin
    Layout := TTextLayoutManager.DefaultTextLayout.Create;
    try
      Layout.BeginUpdate;
      try
        Layout.Font.Assign(MsgText.Font);
        Layout.VerticalAlign := MsgText.TextVertAlign;
        Layout.HorizontalAlign := MsgText.TextAlign;
        Layout.WordWrap := MsgText.WordWrap;
        Layout.Trimming := MsgText.Trimming;
        Layout.MaxSize :=
          TPointF.Create(MsgText.Width, TTextLayout.MaxLayoutSize.Y);
        Layout.Text := Text;
      finally
        Layout.EndUpdate;
      end;
      result := round(Layout.Height);
      Layout.Text := 'm';
      result := max(cMinItemHeight, result + round(Layout.Height));
    finally
      Layout.Free;
    end;
  end;

const
  cOffsetMsg = 60 - 40;
  cOffsetDetail = 60 - 42;
var
  MsgType: TMsgType;
  MsgTxt, DetTxt: TListItemText;
  AvailableWidth: single;
begin
  MsgType := TMsgType(AItem.Tag);
  MsgTxt := TListItemText(AItem.View.FindDrawable(GetMsgTextName(MsgType)));
  DetTxt := TListItemText(AItem.View.FindDrawable(GetDetailTextName(MsgType)));
  AvailableWidth := lsvChat.Width - lsvChat.ItemSpaces.Left -
    lsvChat.ItemSpaces.Right - abs(MsgTxt.PlaceOffset.X);
  lsvChat.BeginUpdate;
  try
    MsgTxt.Width := AvailableWidth;
    AItem.Height := CalcHeight(MsgTxt, AItem.Text);
    MsgTxt.Width := AvailableWidth;
    MsgTxt.Height := AItem.Height;
    DetTxt.PlaceOffset.Y := AItem.Height - cOffsetDetail;
  finally
    lsvChat.EndUpdate;
  end;
end;

function TfmxChatMain.AddProfileImgToImageList(const UID: string;
  Img: TBitmap): integer;
var
  SrcItem: TCustomSourceItem;
  DstItem: TCustomDestinationItem;
  BmpItem: TCustomBitmapItem;
begin
  result := ImageList.Source.IndexOf(UID);
  if result < 0 then // Profile already stored in case ro re-login?
  begin
    SrcItem := ImageList.Source.Add;
    SrcItem.Name := UID;
    BmpItem := SrcItem.MultiResBitmap.Add;
    BmpItem.Scale := 1;
    BmpItem.Bitmap.Assign(Img);
    DstItem := ImageList.Destination.Add;
    with DstItem.Layers.Add do
    begin
      Name := UID;
      SourceRect.Rect := RectF(0, 0, BmpItem.Width, BmpItem.Height);
    end;
    with DstItem.Layers.Add do
    begin
      Name := 'ProfileMask';
      SourceRect.Rect := RectF(0, 0, BmpItem.Width, BmpItem.Height);
    end;
    result := DstItem.Index;
  end else
    dec(result);
end;

procedure TfmxChatMain.DownloadProfileImgAndAddToImageList(const UID: string;
  Item: TListViewItem);
var
  Profile: TPendingProfile;
begin
  if fPendingProfiles.TryGetValue(UID, Profile) then
    Profile.Items.Add(Item)
  else begin
    fPendingProfiles.Add(UID, TPendingProfile.Create(Item));
    GetStorage; // Ensure that Bucket is sent to Config
    fConfig.Storage.Get(TFraSelfRegistration.cDefaultStoragePathForProfileImg +
      '/' + UID, OnGetStorage, nil);
  end;
end;

procedure TfmxChatMain.OnGetStorage(const ObjName: string; Obj: IStorageObject);
var
  Profile: TPendingProfile;
  UID: string;
begin
  UID := Obj.ObjectName(false);
  Profile := fPendingProfiles.Items[UID];
  Assert(assigned(Profile), 'Invalid profile');
  Obj.DownloadToStream(ObjName, Profile.Stream, OnStorageDownload, nil);
end;

procedure TfmxChatMain.OnStorageDownload(const ObjName: string;
  Obj: IStorageObject);
var
  Profile: TPendingProfile;
  Bmp: TBitmap;
  Ind: integer;
  Item: TListViewItem;
  UID: string;
begin
  UID := Obj.ObjectName(false);
  Profile := fPendingProfiles.Items[UID];
  Assert(assigned(Profile), 'Invalid profile');
  Profile.Stream.Position := 0;
  Bmp := TBitmap.Create;
  try
    Bmp.LoadFromStream(Profile.Stream);
    Ind := AddProfileImgToImageList(UID, Bmp);
  finally
    Bmp.Free;
  end;
  lsvChat.BeginUpdate;
  try
    for Item in Profile.Items do
      Item.Data['Image2'] := Ind;
  finally
    lsvChat.EndUpdate;
  end;
  fPendingProfiles.Remove(UID);
  Profile.Free;
end;

{ TfmxChatMain.TPendingProfile }

constructor TfmxChatMain.TPendingProfile.Create(FirstItem: TListViewItem);
begin
  Items := TList<TListViewItem>.Create;
  Items.Add(FirstItem);
  Stream := TMemoryStream.Create;
end;

destructor TfmxChatMain.TPendingProfile.Destroy;
begin
  Stream.Free;
  Items.Free;
  inherited;
end;

end.
