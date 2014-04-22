unit LockCadastro.Unt;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Mask, Buttons;

type
  Tcadastro = class(TForm)
    Label1: TLabel;
    Nome: TEdit;
    Label2: TLabel;
    CPF: TEdit;
    telefone: TMaskEdit;
    Label3: TLabel;
    Label4: TLabel;
    endereco: TEdit;
    Label5: TLabel;
    cidade: TEdit;
    Label6: TLabel;
    estado: TEdit;
    SpeedButton2: TSpeedButton;
    procedure SpeedButton2Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);

  private
    { Private declarations }
    PodeFecharC: Boolean;
    function ValidaCPFCNPJ(CPFCNPJ: string): boolean;
    function FormataCNPJ(Numero: String): String;
    function FormataCPF(Numero: String): String;
    function FormataCNPJ_CPF(Numero: String): String;
  public
    { Public declarations }
  end;

var
  cadastro: Tcadastro;


implementation


{$R *.dfm}

function TCadastro.ValidaCPFCNPJ(CPFCNPJ: string): boolean;
var
count, tam, i, soma: integer;
num: array of integer;
begin
Result:=False;
tam:=0;
SetLength(num,tam);
for i:=1 to Length(CPFCNPJ) do
if CPFCNPJ[i] in ['0'..'9'] then
begin
inc(tam);
SetLength(num,tam);
Val(CPFCNPJ[i],num[tam-1],soma);
end;

if not(tam in [11,14]) then Exit;

count:=2;
soma:=0;
for i:=Length(num)-3 downto 0 do
begin
soma:=soma+(num[i]*count);
inc(count);
if (tam = 14) and (count > 9) then count:=2;
end;
soma:=11-(soma mod 11);
if soma > 9 then soma:=0;

if not(num[tam-2]=soma) then Exit;

soma:=soma*2;
count:=3;
for i:=Length(num)-3 downto 0 do
begin
soma:=soma+(num[i]*count);
inc(count);
if (tam = 14) and (count > 9) then count:=2;
end;
soma:=11-(soma mod 11);
if soma > 9 then soma:=0;

if not(num[tam-1]=soma) then Exit;

Result:=True;
end;


Function TCadastro.FormataCNPJ(Numero: String): String;
var
tmp,resultado: String;
indx, indx1: integer;
begin
if Length(Numero) < 12 Then
begin
result := '';
exit;
end;

for indx := 1 to Length(Numero) do
begin
if Numero[indx] in ['0'..'9'] Then
resultado := resultado + Numero[indx];
end;
if Length(Resultado) < 14 Then
resultado := StringOfChar('0', 14 - Length(Resultado)) + resultado;
tmp := Copy(resultado,1,2) + '.';
tmp := tmp + Copy(resultado,3,3) + '.';
tmp := tmp + Copy(resultado,6,3) + '/';
tmp := tmp + Copy(resultado,9,4) + '-' + Copy(resultado,13,2);
Result := tmp;
end;


Function TCadastro.FormataCPF(Numero: String): String;
var
tmp,resultado: String;
indx, indx1: integer;
begin
if Length(Numero) < 10 Then
begin
result := '';
exit;
end;

for indx := 1 to Length(Numero) do
begin
if Numero[indx] in ['0'..'9'] Then
resultado := resultado + Numero[indx];
end;
if Length(Resultado) < 11 Then
resultado := StringOfChar('0', 11 - Length(Resultado)) + resultado;
tmp := Copy(resultado,1,3) + '.';
tmp := tmp + Copy(resultado,4,3) + '.';
tmp := tmp + Copy(resultado,7,3) + '-';
tmp := tmp + Copy(resultado,10,2);
Result := tmp;
end;

Function TCadastro.FormataCNPJ_CPF(Numero: String): String;
var
//tamanho:integer;
indx: integer;
resultado: String;
begin
for indx := 1 to Length(Numero) do
begin
if Numero[indx] in ['0'..'9'] Then
resultado := resultado + Numero[indx];
end;

if (Length(resultado) > 11) Then
resultado := FormataCNPJ(resultado)
else
resultado := FormataCPF(resultado);
result := resultado;
end;


procedure Tcadastro.FormClose(Sender: TObject; var Action: TCloseAction);
begin
   if not PodefecharC then
      Action := caNone;
end;

procedure Tcadastro.SpeedButton2Click(Sender: TObject);
begin
   PodeFecharC := False;
   if Nome.Text <> '' then
      begin
         if ( CPF.Text <> '' ) and (not ValidaCPFCNPJ( CPF.Text )) then
            begin
               ShowMessage( 'Cpf informado � inv�lido!' );
            end
         else
            begin
               CPF.Text := FormataCNPJ_CPF( CPF.Text );
               PodefecharC := true;
               Close;
            end;

      end
   else
      ShowMessage( 'Nome Completo n�o informado!' );
end;

end.
