{===============================================================================

                           BIBLIOTECA - DATABASE

==========================================================| Vers�o 13.01.00 |==}

unit Lib.DB;

interface

{ Bibliotecas para Interface }
uses
  {$IFNDEF VER150}
  MidasCon, Data.DBXMySQL,
  {$ENDIF}
  MidasLib, Midas, DB, SqlExpr, DBClient, Provider, Vcl.ExtCtrls, Lib.StrUtils;

{ Constantes }
const
  CONN_NAME_FB    = 'FBConnection';
  CONN_NAME_MYSQL = 'MySQLConnection';
  CONN_NAME_IB    = 'IBConnection';
  DRV_FB          = 'Firebird';
  DRV_MYSQL       = 'MySQL';
  DRV_IB          = 'Interbase';

{ Classes }
type
  TDBServerType = (stMySQL, stFirebird);

  TSQLConnectionM = class(TSQLConnection)
  protected
    FSQLDataSet      : TSQLDataSet;
    FDataSetProvider : TDataSetProvider;

    function ApplyParamValues(Args: Variant): Boolean;
  public
    destructor Destroy; override;

    function ExecuteQuery(AQuery: string; const Args: array of Variant): Boolean; overload;
    function ExecuteQuery(AQuery: string): Boolean; overload;
    function ExecuteQuery(var ACds: TClientDataSet; AQuery: string): Boolean; overload;

    function ExecuteQuery(var ACds: TClientDataSet; AQuery: string;
      const Args: array of Variant): Boolean; overload;
  published
    CdsDynamic : TClientDataSet;
  end;

{ Prot�tipos - Fun��es e Procedimentos }
  function  QueryUpperCase(S: string): string;
  function  sParam(S: String): string;

  function  BuildClause(var CDS_Origem: TClientDataSet; sFieldOri,
    sFieldClau: string): string; overload;
  function  BuildClause(AClauseField: string; const Args: array of string): string; overload;
  procedure AddWhere(var ADest: string; const ANewCondition: string;
    ALinker: string = 'AND'); overload;
  function  Booleano(S: String): Boolean; overload;
  function  Booleano(Flag: Boolean): string; overload;

  procedure FeedCdsTemp(ACdsSource: TClientDataSet; var ACdsTarget: TClientDataSet;
    AOverwrite: Boolean = False);
  procedure CopyToCdsTemp(CdsSource: TClientDataSet; var CdsTemp: TClientDataSet);
  procedure CloneCdsFields(CdsSource: TClientDataSet; var CdsTemp: TClientDataSet);
  procedure RecreateCDS(var CDS: TClientDataSet);
  function  FeedStoredProcParams(CdsSource: TClientDataSet;
    var SQLProc: TSQLStoredProc): Boolean;

  function  ClientHasRec(CDS: TClientDataSet; sField, sValue: string): Boolean;
  function  ClientFindRec(DataSet: TDataSet; sField: String; Value: Variant): Integer;
  function  GetMaxFieldValue(DataSet: TDataSet; sField: String): Variant;
  function  GetMinFieldValue(DataSet: TDataSet; sField: String): Variant;
  function  FieldSUM(DataSet: TDataSet; sField: String): Real;
  procedure ExtractDBFile(DataSet: TDataSet; sBlobField, sDestiny: string);
  procedure LoadDBPicture(DataSet: TDataSet; sBlobField: string;
    var ImgDestiny: TImage);
  function  GetFieldType(const S: string): TFieldType;
  function  NewMySQLConn(const AHost: string; const APort: integer;
    const ADBName, AUser, APasswd: string): TSQLConnectionM;
  function  NewFirebirdConn(const AHost: string; const APort: integer;
    const ADBFile, AUser, APassword: string): TSQLConnectionM;
  function  NewInterbaseConn(const AHost: string; const APort: integer;
    const ADBFile, AUser, APassword: string): TSQLConnectionM;

{ Prot�tipos - Apenas para Delphi 7 }
  {$IFDEF VER150}
  function  ExecuteQuery(var AConnection: TSQLConnection; var ACds: TClientDataSet;
    AQuery: string): Boolean; overload; deprecated;
  function  ExecuteQuery(var AConnection: TSQLConnection; var ACds: TClientDataSet;
    AQuery: string; const Args: array of Variant): Boolean; overload;  deprecated;
  function  SetParamValues(var ASqlDs: TSQLDataSet; Args: Variant): Boolean; overload;
  function  SetParamValues(var ASqlDs: TSQLDataSet; Args: array of const): Boolean; overload;
  {$ENDIF}

implementation

{ Bibliotecas para Implementa��o }
uses
  Classes, SysUtils, StrUtils, Vcl.Forms, Vcl.Dialogs, Lib.Utils, Variants, Lib.Files,
  Math, Windows;


{*******************************************************************************

                                TSQLCONNECTIONM

*******************************************************************************}

//==| Desconstrutor |===========================================================
destructor TSQLConnectionM.Destroy;
begin
  try                                                                           //Tento
    if Assigned(Self.FSQLDataSet)      then FreeAndNil(Self.FSQLDataSet);       //Destruir o TSQLDataSet din�mico
    if Assigned(Self.FDataSetProvider) then FreeAndNil(Self.FDataSetProvider);  //e o TDataSetProvider tamb�m, se necess�rio

    if Assigned(Self.CdsDynamic) then                                           //No caso de haver um ClientDataSet inst�nciado, verifico
      if Self.CdsDynamic.Owner = Self then FreeAndNil(Self.CdsDynamic)          //se ele pertence ao SQLConnection e, caso perten�a, o destruo
      else                                 Self.CdsDynamic := nil;              //caso contr�rio apenas removo a refer�ncia ao objeto
  except                                                                        //Se n�o conseguir
    on e: Exception do                                                          //gero um log em arquivo com o erro
      Lib.Files.Log('ExecuteQuery: Falha ao destruir componentes din�micos: ' + e.Message);
  end;

  inherited Destroy;                                                            //Por fim executo o desconstrutor herdado
end;

{==| Fun��o - Colocar Par�metros |==============================================
    Itera um array de Variable, e coloca o valor de cada item em um par�metro
  com o mesmo �ndice (se existir) no SQLDataSet.
  Par�metros de entrada:
    1. Lista de valores dos par�metros da query > Vetor de vari�veis
  Retorno: Sucesso (Boolean)
============================================| Leandro Medeiros (28/11/2013) |==}
function TSQLConnectionM.ApplyParamValues(Args: Variant): Boolean;
var
  idx : integer;
begin
  Result := False;                                                              //Assumo Falha

  if not Assigned(Self.FSQLDataSet) then Exit;                                  //Caso o TSQLDataSet din�mico n�o esteja instanciado, abandono a rotina

  try                                                                           //Caso contr�rio tento
    for idx := 0 to VarArrayHighBound(Args, 1) do                               //iterar os itens do array
      Self.FSQLDataSet.Params[idx].Value := Args[idx];                          //e copiar seus valores para os par�metros do TSQLDataSet
    Result := True;                                                             //Se conseguir copiar todos, retorno verdadeiro
  except                                                                        //Em caso de erro
    on e: Exception do                                                          //gravo a mensagem no log em arquivo
      Lib.Files.Log('Falha ao setar par�metros no SQLDataSet. Erro: ' + e.Message);
  end;
end;

{==| Fun��o - Executa Query |===================================================
    Cria din�micamente todos os componentes necess�rios para executar uma query,
  e alimenta um TClientDataSet.
  Par�metros de entrada:
    1. Query a ser executada > String��

  Retorno: Obteve registros na busca (Booleano).
============================================| Leandro Medeiros (20/10/2011) |==}
function TSQLConnectionM.ExecuteQuery(AQuery: string): Boolean;
begin
  Result := Self.ExecuteQuery(AQuery, []);
end;

{==| Fun��o - Executa Query |===================================================
    Cria din�micamente todos os componentes necess�rios para executar uma query,
  e alimenta um TClientDataSet.
  Par�metros de entrada:
    1. Query a ser executada               > String.
    2. Valores para os par�metros da Query > Vetor de Vari�veis.

  Retorno: Obteve registros ao executar a query (Booleano).
============================================| Leandro Medeiros (28/11/2013) |==}
function TSQLConnectionM.ExecuteQuery(AQuery: string;
  const Args: array of Variant): Boolean;
begin
  Result := Self.ExecuteQuery(Self.CdsDynamic, AQuery, Args);
end;

{==| Fun��o - Executa Query |===================================================
    Cria din�micamente todos os componentes necess�rios para executar uma query,
  e alimenta um TClientDataSet.
  Par�metros de entrada:
    1. Vari�vel que receber� os resultados > TClientDataSet
    2. Query a ser executada               > String��
  Retorno: Obteve registros na busca (Booleano).
============================================| Leandro Medeiros (20/10/2011) |==}
function TSQLConnectionM.ExecuteQuery(var ACds: TClientDataSet; AQuery: string): Boolean;
begin
  Result := Self.ExecuteQuery(ACds, AQuery, []);
end;

{==| Fun��o - Executa Query |===================================================
    Cria din�micamente todos os componentes necess�rios para executar uma query,
  e alimenta um TClientDataSet.
  Par�metros de entrada:
    1. Vari�vel que receber� os resultados > TClientDataSet.
    2. Query a ser executada               > String.
    3. Valores para os par�metros da Query > Vetor de Vari�veis.

  Retorno: Obteve registros ao executar a query (Booleano).
============================================| Leandro Medeiros (20/10/2011) |==}
function TSQLConnectionM.ExecuteQuery(var ACds: TClientDataSet; AQuery: string;
  const Args: array of Variant): Boolean;
const
  DSP_NAME = 'DataSetProviderDinamico';
var
  WasConnected : Boolean;
begin
  Result                := False;                                               //Assumo falha
  WasConnected          := Self.Connected;                                      //Guardo o estado da conex�o antes do processamento
  Self.FSQLDataSet      := nil;
  Self.FDataSetProvider := nil;

  if Self.DriverName = DRV_FB then                                              //Retiro os espa�os e coloco todos
    AQuery := Lib.DB.QueryUpperCase(Trim(AQuery));                              //os caracteres da query em letras mai�sculas

  try                                                                           //Tento
    Self.FSQLDataSet               := TSQLDataSet.Create(Self);                 //instanciar o SQLDataSet,
    Self.FSQLDataSet.SQLConnection := Self;                                     //amarro a conex�o
    Self.FSQLDataSet.CommandText   := AQuery;                                   //Copio a query para a propriedade "Linha de Comando" do SQLDataSet din�mico
    Self.ApplyParamValues(VarArrayOf(Args));                                    //Defino os valores dos par�metros da query

    if not (Copy(AQuery, 1, 6) = 'SELECT') then                                 //Se a query n�o iniciar com o comando SELECT
    begin
      Self.FSQLDataSet.ExecSQL();                                               //devo apenas executar o SQL
      Result := True;                                                           //e retornar sucesso
    end

    else begin                                                                  //Caso contr�rio
      if not Assigned(ACds) then                                                //Se n�o houver um TClientDataSet criado
        ACds := TClientDataSet.Create(Self)                                     //o instancio
      else if ACds.Active then                                                  //sen�o, caso ele esteja ativo
        ACds.EmptyDataSet;                                                      //limpo os registros dele

      ACds.Active := False;                                                     //me certifico que o mesmo esteja desativado

      Self.FDataSetProvider         := TDataSetProvider.Create(ACds.Owner);     //tento instanciar o provedor de dados,
      Self.FDataSetProvider.Name    := DSP_NAME;                                //e nomeio o objeto
      Self.FDataSetProvider.DataSet := Self.FSQLDataSet;                       	//amarro o TSQLDataSet

      ACds.ProviderName  	    := DSP_NAME;                                      //e amarro o Provedor de dados din�mico.

      Self.FSQLDataSet.Active := True;                                    		  //Finalmente ativo o SQLDataSet executando a busca

      ACds.PacketRecords := - 1;                                                //Me certifico que o Client est� sem limitador de pacote de registros (caso contr�rio o client s� receber� os primeiros X registros da busca e depois que o SQLDataSet for destru�do n�o ser� poss�vel mov�-lo)
      ACds.Active        := True;                                               //Ativo o ClientDataSet
      ACds.ProviderName  := EmptyStr;                                           //Retiro seu Provedor de Dados

      Result := not ACds.IsEmpty;                                               //Retorno verdadeiro caso a busca tenha retornado ao menos um resultado
    end;
  finally                                                                       //Ao final sempre
    Self.Connected          := WasConnected;                                    //volto a conex�o ao seu estado inicial
    Self.FSQLDataSet.Active := False;                                           //Desativo o TSQLDataSet

    try                                                                         //Tento
      if Assigned(Self.FSQLDataSet)      then FreeAndNil(Self.FSQLDataSet);     //Destruir o TSQLDataSet din�mico
      if Assigned(Self.FDataSetProvider) then FreeAndNil(Self.FDataSetProvider);//e o TDataSetProvider tamb�m, se necess�rio
    except                                                                      //caso n�o consiga
      on e: Exception do                                                        //gero um log em arquivo com o erro
        Lib.Files.Log('ExecuteQuery: Falha ao destruir componentes din�micos: ' + e.Message);
    end;
  end;
end;


{*******************************************************************************

                            FUN��ES E PROCEDIMENTO

*******************************************************************************}

{==| Fun��o - Query Mai�scula |=================================================
    Muda todos os caracteres de uma string para mai�scula, exceto aqueles que
  est�o entre ap�strofos (par�metros).
============================================| Leandro Medeiros (20/10/2011) |==}
function QueryUpperCase(S: string): string;
var
  idx     : integer;
  InParam : Boolean;
begin
  InParam := False;

  for idx := 1 to Length(S) do
    if S[idx] = Chr(39) then InParam := not InParam
    else if not InParam then S[idx]  := AnsiUpperCase(S[idx])[1];
  Result := S;
end;

{==| Fun��o - Par�metro String |================================================
    Valida um par�metro do tipo string para ser utilizado na fun��o ExecutaQuery.
  Recebe o valor do par�metro em uma string e o retorna concatenado entre
  ap�strofos.
============================================| Leandro Medeiros (20/10/2011) |==}
function sParam(S: String): string;
begin
  if S <> EmptyStr then
    Result := ifthen(Pos('=', S) = 0, '=') + QuotedStr(S)
  else
    Result := ' IS NULL ';
end;

{==| Fun��o - Constr�i Cl�usula |===============================================
    Monta uma cl�usula para ser usada em um WHERE no lugar de um IN. S� pode ser
  usada para um �nico campo de uma �nica tabela.

  Par�metros de entrada:
    1. Client de Origem                                       > TClientDataSet
    2. Campo da Origem (ser� copiado do client pro resultado) > String
    3. Campo Cl�usula (ser� a cl�usula no resultado)          > String
  Retorno: Cl�usula com valores concatenados (string)
============================================| Leandro Medeiros (01/11/2011) |==}
function BuildClause(var CDS_Origem: TClientDataSet; sFieldOri,
  sFieldClau: string): string;
var
  sAux  : string;
  pBook : TBookmark;
begin
  if CDS_Origem.IsEmpty then Exit;                                              //Se o Client de origem estiver vazio aborto o processamento

  sFieldClau := Trim(sFieldClau) + ' = ';                                       //Tiro os espa�os da vari�vel que ser� a condi��o de retorno e adiciono o sinal de igualdade

  with CDS_Origem do
  begin
    pBook := GetBookmark;                                                       //Guardo o �ndice do registro atual do Client
    DisableControls;                                                            //Desativo seus controles
    First;                                                                      //Posiciono no primeiro registro
    while not EOF do                                                            //Fa�o um loop at� o �ltimo registro
    begin                                                                       //onde
      if sAux = '' then                                                         //vefifico se a vari�vel auxiliar est� vazia e caso esteja
        sAux := sFieldClau + QuotedStr(FieldByName(sFieldOri).AsString)         //seu valor passar� a ser o nome do campo cl�usula mais o valor do campo do client configurado na chamada da fun��o
      else                                                                      //caso contr�rio
        sAux := sAux + ' OR ' + sFieldClau + QuotedStr(FieldByName(sFieldOri).AsString); //concateno � ela um "OR" e depois o nome do campo cl�usula mais o valor do campo do client configurado na chamada da fun��o
       Next;                                                                    //Movo o client para o pr�ximo registro
    end;
    if BookmarkValid(pBook) then GotoBookmark(pBook);                           //Se o Bookmark ainda for v�lido, reposiciono o Client a partir dele
    FreeBookmark(pBook);                                                        //libero o marca p�ginas
    EnableControls;                                                             //e reativo os controles
  end;

  if Length(sAux) > 0 then Result := '(' + sAux + ')';                          //Se a vari�vel auxiliar n�o estiver vazia coloco par�nteses no inicio e no fim da string e retorno ela como resultado da fun��o
end;

{==| Fun��o - Constr�i Cl�usula |===============================================
    Monta uma cl�usula para ser usada em um WHERE no lugar de um IN. S� pode ser
  usada para um �nico campo de uma �nica tabela.

  Par�metros de entrada:
    1. Campo Cl�usula (ser� a cl�usula no resultado) > String
    2. Array de Valores                              > String
  Retorno: Cl�usula com valores concatenados (string)
============================================| Leandro Medeiros (01/11/2011) |==}
function BuildClause(AClauseField: string; const Args: array of string): string;
var
  idx  : integer;
begin
  Result       := EmptyStr;
  AClauseField := Trim(AClauseField) + ' = ';                                   //Tiro os espa�os da vari�vel que ser� a condi��o de retorno e adiciono o sinal de igualdade

  for idx := 0 to (Length(Args) - 1) do
    if Result = EmptyStr then                                                   //vefifico se a vari�vel auxiliar est� vazia e caso esteja
      Result := AClauseField + QuotedStr(Args[idx])                             //seu valor passar� a ser o nome do campo cl�usula mais o valor do campo do client configurado na chamada da fun��o
    else                                                                        //caso contr�rio
      Result := Result + ' OR ' + AClauseField + QuotedStr(Args[idx]);          //concateno � ela um "OR" e depois o nome do campo cl�usula mais o valor do campo do client configurado na chamada da fun��o

  if Length(Result) > 0 then Result := '(' + Result + ')';                      //Se a vari�vel auxiliar n�o estiver vazia coloco par�nteses no inicio e no fim da string e retorno ela como resultado da fun��o
end;

{==| Fun��o - Adiciona "Where" |================================================
    Concatena uma string � outra que ser� usada como cl�usula "WHERE" em uma
  query. Caso a string de destino n�o esteja vazia ent�o colocamos o "AND" ou
  "OR".
============================================| Leandro Medeiros (07/06/2013) |==}
procedure AddWhere(var ADest: string; const ANewCondition: string;
  ALinker: string = 'AND'); overload;
begin
  if Length(ANewCondition) <= 0 then Exit;                                      //Se a nova condi��o estiver vazia, n�o processo mais nada
  if Length(ADest) > 0 then                                                     //Se a vari�vel de destino n�o estiver vazia
    ADest := ADest + #32 + ALinker + #32 + ANewCondition                        //concateno � ela um "AND" e a nova condi��o
  else ADest := ' WHERE ' + ANewCondition;                                      //Caso contr�rio inicio ela com "WHERE" concatenado � nova condi��o
end;

{==| Fun��o - Booleano (Overload 01) |==========================================
  Facilita a interpreta��o de campos Flag que vem do banco de dados.
  Par�metros de Entrada:
    1. Valor > String
  Retorno: Booleano;
============================================| Leandro Medeiros (18/01/2012) |==}
function Booleano(S: String): Boolean; overload;
begin
  S := AnsiUpperCase(S);
  Result := (S = 'S') or (S = 'Y');
end;

{==| Fun��o - Booleano (Overload 02) |==========================================
  Facilita a convers�o de campos Flag que v�o para o banco de dados.
  Par�metros de Entrada:
    1. Valor > Booleano
  Retorno: String;
============================================| Leandro Medeiros (18/01/2012) |==}
function Booleano(Flag: Boolean): string; overload;
begin
  Result := ifthen(Flag, 'S', 'N');
end;

{==| Procedimento - Alimenta Client Tempor�rio |================================
    Copia todos os campos e registros de um ClientDataSet para outro (para
  alimenta��o de um Client tempor�rio).
  Par�metros de entrada:
    1. Origem               > TClientDataSet
    2. Destino (Tempor�rio) > TClientDataSet
    3. Sobreescrever        > Boolean (Se verdadeiro, apaga os registros e
                              campos do destino e copia os da origem, caso
                              contr�rio apenas acrescenta os faltantes -
                              Padr�o: Falso)
============================================| Leandro Medeiros (20/10/2011) |==}
procedure FeedCdsTemp(ACdsSource: TClientDataSet; var ACdsTarget: TClientDataSet;
  AOverwrite: Boolean = False);
var idx: integer;
begin
  if not AOverwrite then
  	AOverwrite := ACdsTarget.FieldCount <= 0;                                   //Se o Cliente de destino n�o conter nenhum campo configuro a fun��o para o modo "Sobreescrever"

  if ACdsSource.FieldCount > ACdsTarget.FieldCount then                         //Se o n�mero de campos do Client de Origem for maior que o de Destino
  begin                                                                         //ent�o
    if AOverwrite then                                                          //Caso esteja no modo de sobre escrita
    begin
      RecreateCds(ACdsTarget);                                                  //Recrio o Client de destino
      ACdsTarget.FieldDefs.Assign(ACdsSource.FieldDefs);                        //e clono os campos do Cliente de Origem para ele
    end

    else begin                                                                  //Caso contr�rio
      for idx := 0 to ACdsSource.FieldCount - 1 do                              //Fa�o um loop com os campos do primeiro Client
      begin
        if ACdsTarget.FindField(ACdsSource.Fields[idx].FieldName) = nil then    //Verifico se o campo atual exite no Client de Destino
          ACdsTarget.Fields.Add(ACdsSource.Fields[idx]);                        //e se n�o exitir copio ele
      end;
    end;
  end;

  try
    if not Assigned(ACdsTarget) or (ACdsTarget.IsEmpty) then                    //Se o Client de destino ou sua variav�l estiver vazio
      ACdsTarget.CreateDataSet;                                                 //crio o DataSet
  except
  end;

{  while not CdsSource.EOF do
  begin
    CdsTemp.CloneCursor(CdsSource, False);
    CdsSource.Next;
  end;}

  ACdsSource.First;                                                             //Posiciono o Cliente de Origem no primeiro registro
  while not ACdsSource.EOF do                                                   //Enquanto n�o chegar �ltimo dos registros
  begin
    Lib.DB.CopyToCdsTemp(ACdsSource, ACdsTarget);                               //posto um novo registro no Client de destino
    ACdsSource.Next;                                                            //e movo o Client de Origem para o pr�ximo registro
  end;
  ACdsTarget.Active := True;                                                    //Ao final ativo o Client de Destino
end;

{==| Procedimento - Copia Para ClientDataSet Tempor�rio |=======================
    Copia o registro atual de um ClientDataSet para outro (para alimenta��o de
  um Client tempor�rio).
  Par�metros de entrada:
    1. Fonte                > TClientDataSet
    2. Destino (Tempor�rio) > TClientDataSet
============================================| Leandro Medeiros (20/10/2011) |==}
procedure CopyToCdsTemp(CdsSource: TClientDataSet; var CdsTemp: TClientDataSet);
var
  idx: integer;
begin
  CdsSource.Edit;                                                               //Mudo o Client de origem para o modo de Edi��o
  CdsTemp.Insert;                                                               //e o de Destino para o modo de inser��o

  for idx := 0 to CdsTemp.FieldCount - 1 do                                     //Mais uma vez fa�o um loop com todos os campos
  begin
    CdsTemp.Fields[idx].Required := False;
    CdsTemp.Fields[idx].Value    := CdsSource.FindField(CdsTemp.Fields[idx].FieldName).Value; //E copio o valor de cada um deles para o campo correspondente no Client de Destino
  end;
  CdsTemp.Post;                                                                 //posto o novo registro no Client de destino
  CdsSource.Cancel;                                                             //e cancelo a edi��o do Client de origem
end;

//==| Procedimento - Clona Campos do ClientDataSet |============================
procedure CloneCdsFields(CdsSource: TClientDataSet; var CdsTemp: TClientDataSet);
begin
  CdsTemp.FieldDefs := nil;                                                     //removo poss�veis campos do client de destino
  CdsTemp.FieldDefs.Assign(CdsSource.FieldDefs);                                //e clono os campos do Cliente de Origem para ele
end;

{==| Procedimento - Recriar ClientDataSet |=====================================
    Recebe um ClientDataSet como par�metro, o destroi e logo depois cria novamente
  com o mesmo nome e dono.
============================================| Leandro Medeiros (20/10/2011) |==}
procedure RecreateCds(var CDS: TClientDataSet);
var
  cOwner : TComponent;
  sName  : string;
begin
  sName  := CDS.Name;                                                           //Guardo o antigo nome
  cOwner := CDS.Owner;                                                          //e o dono do ClientDataSet recebido como par�metro

  FreeAndNil(CDS);                                                              //Destruo o componente e esvazio sua vari�vel
  CDS      := TClientDataSet.Create(cOwner);                                    //Recrio usando o dono guardado
  CDS.Name := sName;                                                            //e nomeio com a string antiga
end;

{==| Fun��o - Alimenta Par�metros de Stored Procedure |=========================
    Varre os campos de uma SQLStoredProcedure em busca de par�metros que possuam
  os mesmos nomes que os campos de um ClientDataSet, e copia os valores do segundo
  para o primeiro. Retorna verdadeiro se executar com sucesso.
===============================================================================}
function FeedStoredProcParams(CdsSource: TClientDataSet;
  var SQLProc: TSQLStoredProc): Boolean;
var
  idx : integer;
begin
  try
    for idx := 0 to (CdsSource.Fields.Count - 1) do
      if not CdsSource.Fields[idx].IsNull then
        SQLProc.Params.FindParam(CdsSource.Fields[idx].FieldName).Value := CdsSource.Fields[idx].Value;
    Result := True;
  except
    Result := False;
  end;
end;

{==| Fun��o - Client Possui Registro |==========================================
    Varre um ClientDataSet em busca de determidado valor, e caso o encontre,
  retorna verdadeiro.
  Par�mentros de Entrada:
    1. DataSet que ser� varrido       > TClientDataSet
    2. Nome do campo a ser verificado > String
    3. Valor procurado                > String
  Retorno: Cont�m ou n�o (Booleano)
===============================================================================}
function ClientHasRec(CDS: TClientDataSet; sField, sValue: string): Boolean;
var
  pBook : TBookmark;
begin
  Result := False;                                                              //Pr�-defino o retorno da fun��o como falso
  Try
    pBook  := CDS.GetBookmark;                                                  //Guardo a posi��o (registro) atual do TClientDataSet
    CDS.DisableControls;                                                        //Desativo todos os controles relacionados ao client
    CDS.First;                                                                  //o posiciono no primeiro registro

    while not CDS.EOF do                                                        //Enquanto n�o atingir o final do arquivo
    begin
      if (CDS.FieldByName(sField).AsString = sValue) then                       //Verifico se o valor deste registro � igual ao do par�metro de entrada da fun��o
      begin                                                                     //e se for
        Result := True;                                                         //O retorno da fun��o passa a ser verdadeiro
        CDS.EnableControls;                                                     //Reativo todos os controles relacionados ao client
        Exit;                                                                   //e a busca � finalizada
      end;
      CDS.Next;                                                                 //Se chegar aqui movo o ClientDataSet para pr�ximo registro
    end;
    CDS.EnableControls;                                                         //Reativo todos os controles relacionados ao client
  finally                                                                       //Ao final, sempre
    try                                                                         //tento
      if CDS.BookmarkValid(pBook) then
        CDS.GotoBookmark(pBook);                                                //reposicionar o Client no registro que estava antes de iniciar a procedure
    except
    end;
  end;
end;

{==| Fun��o - Encontrar Registro |==============================================
    Busca um registro dentro de um DataSet e retorna o �ndice caso encontre, caso
  contr�rio retorna -1.
  Par�metros de Entrada:
    1. DataSet onde a busca ser� efetuada > TDataSet
    2. Nome do campo a ser verificado     > String
    3. Valor Procurado                    > Variant
  Retorno: �ndice da string na lista (Integer)
============================================| Renan Vasconcelos(15/03/2012) |==}
function ClientFindRec(DataSet: TDataSet; sField: String; Value: Variant): Integer;
begin
  Result := - 1;

  DataSet.First;
  while not DataSet.EOF do
  begin
    if DataSet.FieldByName(sField).Value = Value then
    begin
      Result := DataSet.RecNo;
      Exit;
    end;
    DataSet.Next;
  end;
end;

{==| Fun��o - Obter Valor M�ximo do Campo |=====================================
    Varre um TDataSet e retorna o maior valor encontrado em determinado campo.
  Par�mentros de Entrada:
    1. DataSet que ser� varrido       > TDataSet ou herdeiros
    2. Nome do campo a ser verificado > String
  Retorno: Variante

  ATEN��O! Este m�todo funciona somente com campos que cont�m valores que possam
  ser ordenados num�ricamente de forma crescente. � mais recomend�vel utilizar
  com os tipos Integer e Float, por�m tamb�m funcionar� com TDateTime e strings
  que possuam unicamente n�meros, como � o caso da maioria das chaves prim�rias
  e estrangeiras do sistema.
===============================================================================}
function GetMaxFieldValue(DataSet: TDataSet; sField: String): Variant;
var
  Value : Variant;
  pBook : TBookmark;
begin
  Value := 0;                                                                   //Inicializo a vari�vel para garantir que nenhum lixo de mem�ria ser� comparado
  with DataSet do                                                               //Amarro o DataSet e
  begin
    DisableControls;                                                            //desabilito os controles
    pBook := GetBookmark;                                                       //guardo a posi��o atual

    First;                                                                      //posiciono no primeiro registro
    while not EOF do                                                            //e enquanto n�o chegar ao �ltimo
    begin
      if FieldByName(sField).Value > Value then                                 //verifico se o valor do campo no registro atual � maior do que o que tenho guardado na vari�vel de retorno (Value)
        Value := FieldByName(sField).Value;                                     //e se for, substituo ela
      Next;                                                                     //depois movo o DataSet para o pr�ximo registro
    end;

    if BookmarkValid(pBook) then GotoBookmark(pBook);                           //Depois de varrer o DataSet, tento volt�-lo para o registro que estava antes da busca
    EnableControls;                                                             //reativo os controles
  end;
  Result := Value;                                                              //e retorno o maior valor encontrado
end;

{==| Fun��o - Obter Valor M�nimo do Campo |=====================================
    Varre um TDataSet e retorna o menor valor encontrado em determinado campo.
  Par�mentros de Entrada:
    1. DataSet que ser� varrido       > TDataSet ou herdeiros
    2. Nome do campo a ser verificado > String
  Retorno: Variante

  ATEN��O! Este m�todo funciona somente com campos que cont�m valores que possam
  ser ordenados num�ricamente de forma decrescente. � mais recomend�vel utilizar
  com os tipos Integer e Float, por�m tamb�m funcionar� com TDateTime e strings
  que possuam unicamente n�meros, como � o caso da maioria das chaves prim�rias
  e estrangeiras do sistema.
===============================================================================}
function GetMinFieldValue(DataSet: TDataSet; sField: String): Variant;
var
  Value : Variant;
  pBook : TBookmark;
begin
  Value := 0;                                                                   //Inicializo a vari�vel para garantir que nenhum lixo de mem�ria ser� comparado
  with DataSet do                                                               //Amarro o DataSet e
  begin
    DisableControls;                                                            //desabilito os controles
    pBook := GetBookmark;                                                       //guardo a posi��o atual

    First;                                                                      //posiciono no primeiro registro
    while not EOF do                                                            //e enquanto n�o chegar ao �ltimo
    begin
      if FieldByName(sField).Value < Value then                                 //verifico se o valor do campo no registro atual � menor do que o que tenho guardado na vari�vel de retorno (Value)
        Value := FieldByName(sField).Value;                                     //e se for, substituo ela
      Next;                                                                     //depois movo o DataSet para o pr�ximo registro
    end;

    if BookmarkValid(pBook) then GotoBookmark(pBook);                           //Depois de varrer o DataSet, tento volt�-lo para o registro que estava antes da busca
    EnableControls;                                                             //reativo os controles
  end;
  Result := Value;                                                              //e retorno o menor valor encontrado
end;

{==| Fun��o - Somar Campo |=====================================================
    Varre um TDataSet somando os valores de um determinado campo.
  Par�mentros de Entrada:
    1. DataSet que ser� varrido   > TDataSet ou herdeiros
    2. Nome do campo a ser somado > String
  Retorno: Real
===============================================================================}
function FieldSUM(DataSet: TDataSet; sField: String): Real;
var
  pBookmark : TBookmark;
  rSum      : Real;
begin
  sField := AnsiUpperCase(sField);

  if not (DataSet.FieldByName(sField).ClassType = TFloatField) and
     not (DataSet.FieldByName(sField).ClassType = TIntegerField) then
  begin
    Result := 0;
    Exit;
  end;

  rSum := 0;

  with DataSet do
  begin
    DisableControls;
    pBookmark := GetBookmark;

    while not EOF do
    begin
      rSum := rSum + DataSet.FieldByName(sField).AsFloat;
      Next;
    end;

    GotoBookmark(pBookmark);
    EnableControls;

    Result := rSum;
  end;
end;

{==| Procedimento - Extrair Arquivo do Banco |==================================
    Varre um campo do tipo Blob bin�rio e a partir dele "monta" um arquivo em
  disco.
  Par�metros de Entrada:
    1. DataSet onde a busca foi feita     > Qualquer herdeiro da classe TDataSet
    2. Nome do campo de origem do arquivo > String
    3. Destino do arquivo                 > String
===============================================================================}
procedure ExtractDBFile(DataSet: TDataSet; sBlobField, sDestiny: string);
var
  Blob : TStream;
begin
  try
    sBlobField := AnsiUpperCase(sBlobField);
    Blob := DataSet.CreateBlobStream(TBlobField(DataSet.FieldByName(sBlobField)),
                                     bmRead);
    Blob.Seek(0, soFromBeginning);

    with TFileStream.Create(sDestiny, fmCreate) do
      try
        CopyFrom(Blob, Blob.Size);
      finally
        Free;
      end;
  finally
    Blob.Free;
  end;
end;

{==| Procedimento - Carregar Imagem do Banco |==================================
    Varre um campo do tipo Blob bin�rio e a partir dele "monta" um arquivo de
  imagem em disco. Depois carrega esta imagem em um componente da classe TImage.
  Par�metros de Entrada:
    1. DataSet onde a busca foi feita     > Qualquer herdeiro da classe TDataSet
    2. Nome do campo de origem do arquivo > String
    3. Destino do arquivo                 > TImage
===============================================================================}
procedure LoadDBPicture(DataSet: TDataSet; sBlobField: string; var ImgDestiny: TImage);
var
  sTempFile : string;
  Blob      : TStream;
begin
  try
    sBlobField := AnsiUpperCase(sBlobField);

    if (DataSet.FieldByName(sBlobField).IsNull) or
       (not DataSet.FieldByName(sBlobField).IsBlob) then
      Exit;

    Blob := DataSet.CreateBlobStream(TBlobField(DataSet.FieldByName(sBlobField)),
                                     bmRead);
    Blob.Seek(0, soFromBeginning);

    sTempFile := GetEnvironmentVariable('TEMP') + '\' + GenRandomStr() + '.png';

    with TFileStream.Create(sTempFile, fmCreate) do
      try
        CopyFrom(Blob, Blob.Size);
      finally
        Free;
      end;

    ImgDestiny.Picture.LoadFromFile(sTempFile);
  finally
    Blob.Free;
    if SysUtils.FileExists(sTempFile) then
      SysUtils.DeleteFile(sTempFile);
  end;
end;

{==| Fun��o - Obter tipo de campo |=============================================
    A partir de uma string determino em que tipo de campo ela dever� ser salva
  no caso de um ClientDataSet tempor�rio din�mico.
  Par�metros de entrada:
    1. Vari�vel � ser avaliada > String
  Retorno:
    Tipo de campo que aceitar� aquela vari�vel (TFieldType)

  NOTA: Ao depurar a aplica��o esta fun��o poder� gerar diversos erros at� que
  retorne um campo.
============================================| Leandro Medeiros (24/11/2011) |==}
function GetFieldType(const S: string): TFieldType;
var
  Aux : Variant;
begin
  try
    Aux    := StrToDate(S);                                                     //Tento converter a string em Data
    Result := ftDate;                                                           //se conseguir retorno tipo data
  except                                                                        //sen�o
    try
      Aux    := StrToInt(S);                                                    //Tento converter a string em Inteiro
      Result := ftInteger;                                                      //se conseguir retorno tipo inteiro
    except                                                                      //caso contr�rio
      try
        Aux    := StrToFloat(S);                                                //Tento converter a string em Float
        Result := ftFloat;                                                      //se conseguir retorno tipo float
      except                                                                    //sen�o
        Result := ftString;                                                     //retorno tipo string
      end;
    end;
  end;
end;

//==| Criar Nova Conex�o com o MySQL |==========================================
function NewMySQLConn(const AHost: string; const APort: integer;
  const ADBName, AUser, APasswd: string): TSQLConnectionM;
const
  MYSQL_PARAMS = 'DriverName=MySQL' +#13+#10
               + 'HostName=%s' +#13+#10
               + 'Database=%s' +#13+#10
               + 'User_Name=%s' +#13+#10
               + 'Password=%s' +#13+#10
               + 'ServerCharSet=' +#13+#10
               + 'BlobSize=-1' +#13+#10
               + 'ErrorResourceFile=' +#13+#10
               + 'LocaleCode=0000' +#13+#10
               + 'Compressed=False' +#13+#10
               + 'Encrypted=False' +#13+#10
               + 'ConnectTimeout=60' +#13#10
               + 'Port=%d' ;
begin
  Result := TSQLConnectionM.Create(nil);

  with Result do
  begin
    Name            := DRV_MYSQL;
    ConnectionName  := CONN_NAME_MYSQL;
    DriverName      := DRV_MYSQL;
    Connected       := False;
    KeepConnection  := False;
    LoginPrompt     := False;

    Params.Text     := Format(MYSQL_PARAMS, [AHost,
                                             ADBName,
                                             AUser,
                                             APasswd,
                                             APort]);
  end;
end;

//==| Criar Nova Conex�o com o Firebird |=======================================
function  NewFirebirdConn(const AHost: string; const APort: integer;
  const ADBFile, AUser, APassword: string): TSQLConnectionM;
const
  FIREBIRD_PARAMS = 'DriverName=Firebird' +#13+#10
                  + 'Database=%s/%d:%s' +#13+#10
                  + 'RoleName=RoleName' +#13+#10
                  + 'User_Name=%s' +#13+#10
                  + 'Password=%s' +#13+#10
                  + 'ServerCharSet=' +#13+#10
                  + 'SQLDialect=3' +#13+#10
                  + 'ErrorResourceFile=' +#13+#10
                  + 'LocaleCode=0000' +#13+#10
                  + 'BlobSize=-1' +#13+#10
                  + 'CommitRetain=False' +#13+#10
                  + 'WaitOnLocks=True' +#13+#10
                  + 'IsolationLevel=ReadCommitted' +#13+#10
                  + 'Trim Char=False';
begin
  Result := TSQLConnectionM.Create(nil);

  Result.Name           := 'SQLFBCon';
  Result.ConnectionName := Lib.DB.CONN_NAME_FB;
  Result.DriverName     := Lib.DB.DRV_FB;
  Result.Connected      := False;
  Result.KeepConnection := False;
  Result.LoginPrompt    := False;
  Result.Params.Text    := Format(FIREBIRD_PARAMS, [AHost,
                                                    Math.ifthen(Bool(APort), APort, 3050),
                                                    ADBFile,
                                                    AUser,
                                                    APassword]);
  try
    Result.Connected := True;
  except
    on e: Exception do
      Lib.Files.Log('Falha de conex�o ao banco de dados: ' + e.Message);
  end;

  Result.Connected := False;
end;

//==| Criar Nova Conex�o com o Firebird |=======================================
function  NewInterbaseConn(const AHost: string; const APort: integer;
  const ADBFile, AUser, APassword: string): TSQLConnectionM;
const
  IB_PARAMS = 'DriverUnit=Data.DBXInterBase' +#13+#10
            + 'DriverPackageLoader=TDBXDynalinkDriverLoader,DbxCommonDriver200.bpl' +#13+#10
            + 'DriverAssemblyLoader=Borland.Data.TDBXDynalinkDriverLoader,Borland.Data.DbxCommonDriver,Version=20.0.0.0,Culture=neutral,PublicKeyToken=91d62ebb5b0d1b1b' +#13+#10
            + 'MetaDataPackageLoader=TDBXInterbaseMetaDataCommandFactory,DbxInterBaseDriver200.bpl' +#13+#10
            + 'MetaDataAssemblyLoader=Borland.Data.TDBXInterbaseMetaDataCommandFactory,Borland.Data.DbxInterBaseDriver,Version=20.0.0.0,Culture=neutral,PublicKeyToken=91d62ebb5b0d1b1b' +#13+#10
            + 'GetDriverFunc=getSQLDriverINTERBASE' +#13+#10
            + ';LibraryName=dbxint.dll' +#13+#10
            + 'LibraryName=dbxfb.dll' +#13+#10
            + 'LibraryNameOsx=libsqlib.dylib' +#13+#10
            + 'VendorLib=fbclient.dll' +#13+#10
            + 'VendorLibWin64=ibclient64.dll' +#13+#10
            + 'VendorLibOsx=libgds.dylib' +#13+#10
            + 'BlobSize=-1' +#13+#10
            + 'CommitRetain=False' +#13+#10
            + 'Database=%s/%d:%s' +#13+#10
            + 'ErrorResourceFile=' +#13+#10
            + 'LocaleCode=0000' +#13+#10
            + 'Password=%s' +#13+#10
            + 'RoleName=RoleName' +#13+#10
            + 'ServerCharSet=' +#13+#10
            + 'SQLDialect=3' +#13+#10
            + 'IsolationLevel=ReadCommitted' +#13+#10
            + 'User_Name=%s' +#13+#10
            + 'WaitOnLocks=True' +#13+#10
            + 'Trim Char=False' +#13+#10
            + 'SEP=' +#13+#10
            + 'DisplayDriverName=InterBase Server';
begin
  Result := TSQLConnectionM.Create(nil);

  Result.Name           := 'SQLIBCon';
  Result.ConnectionName := Lib.DB.CONN_NAME_IB;
  Result.DriverName     := Lib.DB.DRV_IB;
  Result.Connected      := False;
  Result.KeepConnection := False;
  Result.LoginPrompt    := False;
  Result.Params.Text    := Format(IB_PARAMS, [AHost,
                                              Math.ifthen(Bool(APort), APort, 3050),
                                              ADBFile,
                                              APassword,
                                              AUser]);
  Result.Connected := True;
  Result.Connected := False;
end;

{$IFDEF VER150}

{*******************************************************************************

                PROCEDIMENTOS E FUN��ES EXCLUSIVOS DELPHI 7

*******************************************************************************}

function ExecuteQuery(var AConnection: TSQLConnection; var ACds: TClientDataSet;
  AQuery: string): Boolean; overload;
var
  sSqlName,
  sDspName     : string;
  SqlDados     : TSQLDataSet;
  DspDados     : TDataSetProvider;
  WasConnected,
  lgDestroy    : Boolean;

  procedure CreateCds;
  begin
    try
      ACds := TClientDataSet.Create(Application);                               //tento cri�-lo
    except
      Lib.Files.Log('Erro ao instanciar TClientDataSet');
    end;
  end;
begin
  Result       := False;                                                        //Assumo falha
  WasConnected := AConnection.Connected;                                        //Guardo o estado da conex�o antes do processamento
  SqlDados     := nil;
  DspDados     := nil;

  if AConnection.DriverName = DRV_FB then                                       //Retiro os espa�os e coloco todos
    AQuery := QueryUpperCase(Trim(AQuery));                                     //os caracteres da query em letras mai�sculas
  lgDestroy := (Copy(AQuery, 1, 6) = 'SELECT');

  try                                                                           //Tento
    sSqlName               := FindAvaliableName(Application, 'SqlDados');       //(Nomea��o dos componentes din�micos tem de ser diferente)

    SqlDados               := TSQLDataSet.Create(Application);                  //instanciar o SQLDataSet pertencendo ao Dono recebido no par�metro,
    SqlDados.SQLConnection := AConnection;                                      //amarro a conex�o
    SqlDados.Name          := sSqlName;                                         //e nomeio o objeto
    SqlDados.CommandText   := AQuery;                                           //Copio a query para a propriedade "Linha de Comando" do SQLDataSet din�mico

    if not lgDestroy then SqlDados.ExecSQL()                                    //Se a query n�o iniciar com o comando SELECT devo apenas executar o SQL

    else begin                                                                  //Caso contr�rio
      try
        if not Assigned(ACds) or (ACds.Name = EmptyStr) then CreateCds;
      except
        CreateCds;
      end;

      ACds.Active         := False;                                             //me certifico que o mesmo esteja desativado

      sDspName            := FindAvaliableName(ACds.Owner, 'DspDados');
      DspDados            := TDataSetProvider.Create(ACds.Owner);               //tento instanciar o provedor de dados pertencendo ao Dono recebido no par�metro,
      DspDados.Name       := sDspName;                                          //e nomeio o objeto
      DspDados.DataSet    := SqlDados;                                          //amarro o SQLDataSet
      ACds.ProviderName   := sDspName;                                          //e amarro o Provedor de dados din�mico.

      SqlDados.Active     := True;                                              //Finalmente ativo o SQLDataSet executando a busca

      ACds.PacketRecords  := - 1;                                               //Me certifico que o Client est� sem limitador de pacote de registros (caso contr�rio o client s� receber� os primeiros X registros da busca e depois que o SQLDataSet for destru�do n�o ser� poss�vel mov�-lo)
      ACds.Active         := True;                                              //Ativo o ClientDataSet
      ACds.ProviderName   := '';                                                //Retiro seu Provedor de Dados
      Result              := not ACds.IsEmpty;                                  //Retorno verdadeiro caso a busca tenha retornado ao menos um resultado
    end;
  finally                                                                       //Ao final sempre
    AConnection.Connected := WasConnected;                                      //volto a conex�o ao seu estado inicial
    SqlDados.Active       := False;

    if lgDestroy then
      try
        SqlDados.FreeOnRelease;
        SqlDados.Destroy;

        DspDados.FreeOnRelease;
        DspDados.Destroy;
      except
      end;
  end;
end;

{==| Fun��o - Executa Query |===================================================
    Cria din�micamente todos os componentes necess�rios para executar uma query,
  e alimenta um TClientDataSet.
  Par�metros de entrada:
    1. Conex�o a ser utilizada             > TSQLConnection.
    2. Vari�vel que receber� os resultados > TClientDataSet.
    3. Query a ser executada               > String.
    4. Valores para os par�metros da Query > Vetor de Vari�veis.

  Retorno: Obteve registros ao executar a query (Booleano).
============================================| Leandro Medeiros (20/10/2011) |==}
function ExecuteQuery(var AConnection: TSQLConnection; var ACds: TClientDataSet;
  AQuery: string; const Args: array of Variant): Boolean;
var
  WasConnected,
  lgDestroy    : Boolean;
  sSqlName,
  sDspName     : string;
  SqlDados     : TSQLDataSet;
  DspDados     : TDataSetProvider;

  procedure CreateCds;
  begin
    try
      ACds := TClientDataSet.Create(Application);                               //tento cri�-lo
    except
      Lib.Files.Log('Erro ao instanciar TClientDataSet');
    end;
  end;
begin
  Result       := False;                                                        //Assumo falha
  WasConnected := AConnection.Connected;                                        //Guardo o estado da conex�o antes do processamento
  SqlDados     := nil;
  DspDados     := nil;

  if AConnection.DriverName = DRV_FB then                                       //Retiro os espa�os e coloco todos
    AQuery := QueryUpperCase(Trim(AQuery));                                     //os caracteres da query em letras mai�sculas
  lgDestroy := (Copy(AQuery, 1, 6) = 'SELECT');

  try                                                                           //Tento
    sSqlName               := FindAvaliableName(Application, 'SqlDados');       //(Nomea��o dos componentes din�micos tem de ser diferente)

    SqlDados               := TSQLDataSet.Create(Application);                  //instanciar o SQLDataSet pertencendo ao Dono recebido no par�metro,
    SqlDados.SQLConnection := AConnection;                                      //amarro a conex�o
    SqlDados.Name          := sSqlName;                                         //e nomeio o objeto
    SqlDados.CommandText   := AQuery;                                           //Copio a query para a propriedade "Linha de Comando" do SQLDataSet din�mico

    SetParamValues(SqlDados, VarArrayOf(Args));                                 //Defino os valores dos par�metros da query

    if not lgDestroy then SqlDados.ExecSQL()                                    //Se a query n�o iniciar com o comando SELECT devo apenas executar o SQL

    else begin                                                                  //Caso contr�rio
      try
        if not Assigned(ACds) or (ACds.Name = EmptyStr) then CreateCds;
      except
        CreateCds;
      end;

      ACds.Active         := False;                                             //me certifico que o mesmo esteja desativado

      sDspName            := FindAvaliableName(ACds.Owner, 'DspDados');
      DspDados            := TDataSetProvider.Create(ACds.Owner);               //tento instanciar o provedor de dados pertencendo ao Dono recebido no par�metro,
      DspDados.Name       := sDspName;                                          //e nomeio o objeto
      DspDados.DataSet    := SqlDados;                                          //amarro o SQLDataSet
      ACds.ProviderName   := sDspName;                                          //e amarro o Provedor de dados din�mico.

      SqlDados.Active     := True;                                              //Finalmente ativo o SQLDataSet executando a busca

      ACds.PacketRecords  := - 1;                                               //Me certifico que o Client est� sem limitador de pacote de registros (caso contr�rio o client s� receber� os primeiros X registros da busca e depois que o SQLDataSet for destru�do n�o ser� poss�vel mov�-lo)
      ACds.Active         := True;                                              //Ativo o ClientDataSet
      ACds.ProviderName   := '';                                                //Retiro seu Provedor de Dados
      Result              := not ACds.IsEmpty;                                  //Retorno verdadeiro caso a busca tenha retornado ao menos um resultado
    end;
  finally                                                                       //Ao final sempre
    AConnection.Connected := WasConnected;                                      //volto a conex�o ao seu estado inicial
    SqlDados.Active       := False;

    if lgDestroy then
      try
        SqlDados.FreeOnRelease;
        SqlDados.Destroy;

        DspDados.FreeOnRelease;
        DspDados.Destroy;
      except
      end;
  end;
end;

//==| Fun��o - Colocar Par�metros |=============================================
function SetParamValues(var ASqlDs: TSQLDataSet; Args: Variant): Boolean; overload;
var
  idx : integer;
begin
  try
    for idx := 0 to VarArrayHighBound(Args, 1) do
      ASqlDs.Params[idx].Value := Args[idx];
    Result := True;
  except
    Result := False;
  end;
end;

//==| Fun��o - Colocar Par�metros |=============================================
function SetParamValues(var ASqlDs: TSQLDataSet; Args: array of const): Boolean; overload;
var
  idx : integer;
begin
  try
    for idx := 0 to High(Args) do
      case Args[idx].VType of
        { Num�ricos }
        vtInteger:        ASqlDs.Params[idx].AsInteger  := Args[idx].VInteger;
        vtInt64:          ASqlDs.Params[idx].AsInteger  := Args[idx].VInt64^;
        vtExtended:       ASqlDs.Params[idx].AsFloat    := Args[idx].VExtended^;

        { Strings }
        vtChar:           ASqlDs.Params[idx].AsString   := Args[idx].VChar;
        vtString:         ASqlDs.Params[idx].AsString   := Args[idx].VString^;
        vtPChar:          ASqlDs.Params[idx].AsString   := Args[idx].VPChar;
        vtAnsiString:     ASqlDs.Params[idx].AsString   := string(Args[idx].VAnsiString);

        { Outros }
        vtObject:         ASqlDs.Params[idx].AsString   := Args[idx].VObject.ClassName;
        vtClass:          ASqlDs.Params[idx].AsString   := Args[idx].VClass.ClassName;
        vtBoolean:        ASqlDs.Params[idx].AsBoolean  := Args[idx].VBoolean;
        vtCurrency:       ASqlDs.Params[idx].AsCurrency := Args[idx].VCurrency^;
        vtVariant:        ASqlDs.Params[idx].Value      := Args[idx].VVariant^;
      end;
    Result := True;
  except
    Result := False;
  end;
end;
//==============================================================================

{$ENDIF}

end.

