﻿// Marcello Mello
// 28/09/2019

unit LoxLanguage.Interpreter;

interface

uses
  System.SysUtils,
  System.Classes,
  Generics.Collections,
  System.DateUtils,
  Vcl.Dialogs,
  LoxLanguage.Interpreter.Env,
  LoxLanguage.Interpreter.AST,
  LoxLanguage.Interpreter.Types;

type
  TAstInterpreterVisitor = class(TInterfacedObject, IAstVisitor)
  private
    FGlobals: TEnvironment;
    FEnvironment: TEnvironment;
    FLocals: TDictionary<TExpressionNode, Integer>;
    function Evaluate(Expression: TExpressionNode): TLoxValue;
    function IsTruthy(Value: TLoxValue): Boolean;
    function IsEqual(ValueA, ValueB: TLoxValue): Boolean;
    procedure CheckNumberOperands(TokenOperator: TLoxToken; left, Right: TLoxValue);
    function Stringify(Value: TLoxValue): string;
    procedure Execute(Statement: TStatementNode);
    procedure ExecuteBlock(Statements: TObjectList<TStatementNode>; Environment: TEnvironment);
    function LookUpVariable(name: TLoxToken; Expr: TExpressionNode): TLoxValue;
    procedure CheckNumberOperand(Oper: TLoxToken; Operand: TLoxValue);
  private
    function Visit(AssignExpression: TAssignExpressionNode): TLoxValue; overload;
    function Visit(BinaryExpression: TBinaryExpressionNode): TLoxValue; overload;
    function Visit(CallExpression: TCallExpressionNode): TLoxValue; overload;
    function Visit(GeTExpressionNode: TGeTExpressionNode): TLoxValue; overload;
    function Visit(GroupingExpression: TGroupingExpressionNode): TLoxValue; overload;
    function Visit(LiteralExpression: TLiteralExpressionNode): TLoxValue; overload;
    function Visit(LogicalExpression: TLogicalExpressionNode): TLoxValue; overload;
    function Visit(SeTExpressionNode: TSeTExpressionNode): TLoxValue; overload;
    function Visit(SuperExpression: TSuperExpressionNode): TLoxValue; overload;
    function Visit(ThisExpression: TThisExpressionNode): TLoxValue; overload;
    function Visit(UnaryExpression: TUnaryExpressionNode): TLoxValue; overload;
    function Visit(VariableExpression: TVariableExpressionNode): TLoxValue; overload;
    function Visit(BlockStatement: TBlockStatementNode): TLoxValue; overload;
    function Visit(BreakStatement: TBreakStatementNode): TLoxValue; overload;
    function Visit(ContinueStatement: TContinueStatementNode): TLoxValue; overload;
    function Visit(ExpressionStatement: TExpressionStatementNode): TLoxValue; overload;
    function Visit(IfStatement: TIfStatementNode): TLoxValue; overload;
    function Visit(FunctionStatement: TFunctionStatementNode): TLoxValue; overload;
    function Visit(PrintStatement: TPrintStatementNode): TLoxValue; overload;
    function Visit(ClassStatement: TClassStatementNode): TLoxValue; overload;
    function Visit(ReturnStatement: TReturnStatementNode): TLoxValue; overload;
    function Visit(VarStatement: TVarStatementNode): TLoxValue; overload;
    function Visit(WhileStatement: TWhileStatementNode): TLoxValue; overload;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Interpret(Statements: TObjectList<TStatementNode>);
    procedure Resolve(Expr: TExpressionNode; Depth: Integer);
    property Globals: TEnvironment read FGlobals;
  end;

  TCallable = class
  private
  public
    function Call(interpreter: TAstInterpreterVisitor; Arguments: TList<TLoxValue>): TLoxValue; virtual; abstract;
    function Arity(): Integer; virtual; abstract;
  end;

  TClockFunction = class(TCallable)
  public
    function Call(interpreter: TAstInterpreterVisitor; Arguments: TList<TLoxValue>): TLoxValue; override;
    function Arity: Integer; override;
    function ToString(): string; override;
  end;

  EReturnException = class(Exception)
  private
    FValue: TLoxValue;
  public
    constructor Create(Value: TLoxValue);
    property Value: TLoxValue read FValue;
  end;

  EContinueException = class(Exception)
  end;

  EBreakException = class(Exception)
  end;

  TCallableFunction = class;

  TLoxClass = class(TCallable)
  private
    FName: string;
    FMethods: TDictionary<string, TCallableFunction>;
    FSuperclass: TLoxValue;
  public
    constructor Create(name: string; Superclass: TLoxValue; Methods: TDictionary<string, TCallableFunction>);
    function FindMethod(name: string): TCallableFunction;
    function ToString(): string; override;
    function Call(interpreter: TAstInterpreterVisitor; Arguments: TList<TLoxValue>): TLoxValue; override;
    function Arity(): Integer; override;
    property name: string read FName;
  end;

  TLoxObjectInstance = class
  private
    FClass: TLoxClass;
    FFields: TDictionary<string, TLoxValue>;
  public
    constructor Create(AClass: TLoxClass);
    function ToString(): string; override;
    function GetValue(name: TLoxToken): TLoxValue;
    procedure SetValue(name: TLoxToken; Value: TLoxValue);
  end;

  TCallableFunction = class(TCallable)
  private
    FDeclaration: TFunctionStatementNode;
    FClosure: TEnvironment;
    FIsInitializer: Boolean;
  public
    constructor Create(Declaration: TFunctionStatementNode; Closure: TEnvironment; IsInitializer: Boolean);
    function Bind(Instance: TLoxObjectInstance): TLoxValue;
    function Call(interpreter: TAstInterpreterVisitor; Arguments: TList<TLoxValue>): TLoxValue; override;
    function Arity: Integer; override;
    function ToString(): string; override;
  end;

var
  HadRuntimeError: Boolean = false;

implementation

{ TAstInterpreterVisitor }

function TAstInterpreterVisitor.Visit(GroupingExpression: TGroupingExpressionNode): TLoxValue;
begin
  Result := Evaluate(GroupingExpression.Expr);
end;

constructor TAstInterpreterVisitor.Create;
var
  ClockFunction: TLoxValue;
begin
  FGlobals := TEnvironment.Create();
  FEnvironment := FGlobals;

  FLocals := TDictionary<TExpressionNode, Integer>.Create();

  ClockFunction := default(TLoxValue);
  ClockFunction.ValueType := TLoxValueType.IS_CALLABLE;
  ClockFunction.CallableValue := TClockFunction.Create();

  FGlobals.Define('clock', ClockFunction);
end;

destructor TAstInterpreterVisitor.Destroy;
begin
  FEnvironment.Free();
  inherited;
end;

function TAstInterpreterVisitor.Evaluate(Expression: TExpressionNode): TLoxValue;
begin
  Result := Expression.Accept(Self);
end;

function TAstInterpreterVisitor.IsEqual(ValueA, ValueB: TLoxValue): Boolean;
begin

  if (ValueA.ValueType = TLoxValueType.IS_NULL) and (ValueB.ValueType = TLoxValueType.IS_NULL) then
    Result := True
  else if (ValueA.ValueType = TLoxValueType.IS_UNDEF) and (ValueB.ValueType = TLoxValueType.IS_UNDEF) then
    Result := True
  else if (ValueA.ValueType <> ValueB.ValueType) then
    Result := false
  else if (ValueA.ValueType = TLoxValueType.IS_NULL) or (ValueB.ValueType = TLoxValueType.IS_NULL) then
    Result := false
  else if (ValueA.ValueType = TLoxValueType.IS_UNDEF) or (ValueB.ValueType = TLoxValueType.IS_UNDEF) then
    Result := false
  else
  begin
    case ValueA.ValueType of
      TLoxValueType.IS_INT32:
        Result := ValueA.Int32Value = ValueB.Int32Value;
      TLoxValueType.IS_INT64:
        Result := ValueA.Int64Value = ValueB.Int64Value;
      TLoxValueType.IS_DOUBLE:
        Result := ValueA.DoubleValue = ValueB.DoubleValue;
      TLoxValueType.IS_STRING:
        Result := ValueA.DoubleValue = ValueB.DoubleValue;
      TLoxValueType.IS_BOOLEAN:
        Result := ValueA.BooleanValue = ValueB.BooleanValue;
      TLoxValueType.IS_CHAR:
        Result := ValueA.BooleanValue = ValueB.BooleanValue;
      TLoxValueType.IS_CALLABLE:
        Result := ValueA.CallableValue = ValueB.CallableValue;
      TLoxValueType.IS_CLASS:
        Result := ValueA.ClassValue = ValueB.ClassValue;
      TLoxValueType.IS_OBJECT:
        Result := ValueA.ObjectInstanceValue = ValueB.ObjectInstanceValue;
      TLoxValueType.IS_METHOD:
        Result := ValueA.MethodValue = ValueB.MethodValue;
    else
      Result := false;
    end;
  end;

end;

procedure TAstInterpreterVisitor.CheckNumberOperands(TokenOperator: TLoxToken; left, Right: TLoxValue);
begin
  if (left.ValueType = TLoxValueType.IS_DOUBLE) and (Right.ValueType = TLoxValueType.IS_DOUBLE) then
    Exit();

  raise ELoxRuntimeError.Create(TokenOperator, 'Operandos devem ser números.');
end;

function TAstInterpreterVisitor.Visit(BinaryExpression: TBinaryExpressionNode): TLoxValue;
var
  Left, Right: TLoxValue;
begin
  Result := default(TLoxValue);

  Left := Evaluate(BinaryExpression.left);
  Right := Evaluate(BinaryExpression.Right);

  case BinaryExpression.Operador.TokenType of
    TLoxTokenType.NOT_EQUAL_PAIRS_SYMBOL:
      begin
        Result.ValueType := TLoxValueType.IS_BOOLEAN;
        Result.BooleanValue := not IsEqual(Left, Right);
      end;
    TLoxTokenType.EQUAL_EQUAL_PAIRS_SYMBOL:
      begin
        Result.ValueType := TLoxValueType.IS_BOOLEAN;
        Result.BooleanValue := IsEqual(Left, Right);
      end;
    TLoxTokenType.GREATER_SYMBOL:
      begin
        CheckNumberOperands(BinaryExpression.Operador, Left, Right);
        Result.ValueType := TLoxValueType.IS_BOOLEAN;
        Result.BooleanValue := Left.DoubleValue > Right.DoubleValue;
      end;
    TLoxTokenType.GREATER_EQUAL_PAIRS_SYMBOL:
      begin
        CheckNumberOperands(BinaryExpression.Operador, Left, Right);
        Result.ValueType := TLoxValueType.IS_BOOLEAN;
        Result.BooleanValue := Left.DoubleValue >= Right.DoubleValue;
      end;
    TLoxTokenType.LESS_SYMBOL:
      begin
        CheckNumberOperands(BinaryExpression.Operador, Left, Right);
        Result.ValueType := TLoxValueType.IS_BOOLEAN;
        Result.BooleanValue := Left.DoubleValue < Right.DoubleValue;
      end;
    TLoxTokenType.LESS_EQUAL_PAIRS_SYMBOL:
      begin
        CheckNumberOperands(BinaryExpression.Operador, Left, Right);
        Result.ValueType := TLoxValueType.IS_BOOLEAN;
        Result.BooleanValue := Left.DoubleValue <= Right.DoubleValue;
      end;
    TLoxTokenType.MINUS_SYMBOL:
      begin
        CheckNumberOperands(BinaryExpression.Operador, Left, Right);
        Result.ValueType := TLoxValueType.IS_DOUBLE;
        Result.DoubleValue := Left.DoubleValue - Right.DoubleValue;
      end;
    TLoxTokenType.PLUS_SYMBOL:
      begin
        if (Left.ValueType = TLoxValueType.IS_DOUBLE) and (Right.ValueType = TLoxValueType.IS_DOUBLE) then
        begin
          Result.ValueType := TLoxValueType.IS_DOUBLE;
          Result.DoubleValue := Left.DoubleValue + Right.DoubleValue;
        end
        else if (Left.ValueType = TLoxValueType.IS_STRING) and (Right.ValueType = TLoxValueType.IS_STRING) then
        begin
          Result.ValueType := TLoxValueType.IS_STRING;

          Result.StrValue := Left.StrValue + Result.StrValue;

          // StrPas(, Concat(Left.StrValue, Right.StrValue));
        end
        else if (Left.ValueType = TLoxValueType.IS_STRING) or (Right.ValueType = TLoxValueType.IS_STRING) then
        begin
          Result.ValueType := TLoxValueType.IS_STRING;
          Result.StrValue := ShortString(Stringify(Left) + Stringify(Right));

          // StrPas(, Concat(Left.StrValue, Right.StrValue));
        end
        else
          raise ELoxRuntimeError.Create(BinaryExpression.Operador, 'Os operandos devem ter dois números ou duas strings');
      end;
    TLoxTokenType.SLASH_SYMBOL:
      begin
        CheckNumberOperands(BinaryExpression.Operador, Left, Right);

        if (Right.DoubleValue = 0) then
          raise ELoxRuntimeError.Create(BinaryExpression.Operador, 'Divisão por zero.');

        Result.ValueType := TLoxValueType.IS_DOUBLE;
        Result.DoubleValue := Left.DoubleValue / Right.DoubleValue;
      end;
    TLoxTokenType.STAR_SYMBOL:
      begin
        CheckNumberOperands(BinaryExpression.Operador, Left, Right);
        Result.ValueType := TLoxValueType.IS_DOUBLE;
        Result.DoubleValue := Left.DoubleValue * Right.DoubleValue;
      end;
  else
    Result.ValueType := TLoxValueType.IS_NULL;
  end;

end;

function TAstInterpreterVisitor.Visit(LiteralExpression: TLiteralExpressionNode): TLoxValue;
begin
  Result := LiteralExpression.Value;
end;

function TAstInterpreterVisitor.Visit(UnaryExpression: TUnaryExpressionNode): TLoxValue;
var
  Right: TLoxValue;
begin

  Right := Evaluate(UnaryExpression.Right);

  if UnaryExpression.Operador.TokenType = TLoxTokenType.NOT_SYMBOL then
  begin
    Result.ValueType := TLoxValueType.IS_DOUBLE;
    Result.BooleanValue := not IsTruthy(Right);
  end
  else if UnaryExpression.Operador.TokenType = TLoxTokenType.MINUS_SYMBOL then
  begin
    CheckNumberOperand(UnaryExpression.Operador, Right);
    Result.ValueType := TLoxValueType.IS_DOUBLE;
    Result.DoubleValue := -Right.DoubleValue;
  end
  else
    Result.ValueType := TLoxValueType.IS_NULL;

end;

procedure TAstInterpreterVisitor.CheckNumberOperand(Oper: TLoxToken; Operand: TLoxValue);
begin
  if (Operand.ValueType = TLoxValueType.IS_DOUBLE) then
    Exit();

  raise ELoxRuntimeError.Create(Oper, 'O operando deve ser um número.');
end;

function TAstInterpreterVisitor.IsTruthy(Value: TLoxValue): Boolean;
begin

  if (Value.ValueType = TLoxValueType.IS_NULL) then
    Exit(false);

  if (Value.ValueType = TLoxValueType.IS_BOOLEAN) then
    Result := Value.BooleanValue
  else
    Result := True;

end;

function TAstInterpreterVisitor.Stringify(Value: TLoxValue): string;
var
  OldDecimalSeparator: Char;
begin

  if Value.ValueType = TLoxValueType.IS_NULL then
    Result := 'nil'
  else if Value.ValueType = TLoxValueType.IS_DOUBLE then
  begin
    OldDecimalSeparator := FormatSettings.DecimalSeparator;
    try
      FormatSettings.DecimalSeparator := '.';
      Result := FloatToStr(Value.DoubleValue);

      if (Result.EndsWith('.0')) then
        Result := Result.Substring(1, Result.Length - 1);
    finally
      FormatSettings.DecimalSeparator := OldDecimalSeparator;
    end;
  end
  else if Value.ValueType = TLoxValueType.IS_BOOLEAN then
    Result := BoolToStr(Value.BooleanValue)
  else if Value.ValueType = TLoxValueType.IS_STRING then
    Result := string(Value.StrValue)
  else if Value.ValueType = TLoxValueType.IS_INT32 then
    Result := IntToStr(Value.Int32Value)
  else if Value.ValueType = TLoxValueType.IS_INT64 then
    Result := IntToStr(Value.Int32Value)
  else
    Result := '';

end;

function TAstInterpreterVisitor.Visit(WhileStatement: TWhileStatementNode): TLoxValue;
begin
  while IsTruthy(Evaluate(WhileStatement.Condition)) do
  begin
    try
      Execute(WhileStatement.Body);
    except
      on E: EBreakException do
        Break;
      on E: EContinueException do
        Continue;
    end;
  end;

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

function TAstInterpreterVisitor.Visit(ContinueStatement: TContinueStatementNode): TLoxValue;
begin
  raise EContinueException.Create('');
end;

function TAstInterpreterVisitor.Visit(BreakStatement: TBreakStatementNode): TLoxValue;
begin
  raise EBreakException.Create('');
end;

function TAstInterpreterVisitor.Visit(SuperExpression: TSuperExpressionNode): TLoxValue;
var
  Distance: Integer;
  Superclass: TLoxClass;
  Obj: TLoxObjectInstance;
  Method: TCallableFunction;
begin
  Distance := FLocals[SuperExpression];
  Superclass := TLoxClassValue(FEnvironment.GetAt(Distance, 'super').ClassValue);

  Obj := TLoxObjectInstance(FEnvironment.GetAt(Distance - 1, 'this').ObjectInstanceValue);

  Method := Superclass.FindMethod(SuperExpression.Method.Lexeme);

  if (Method = nil) then
    raise ELoxRuntimeError.Create(SuperExpression.Method, 'Propriedade indefinida "' + SuperExpression.Method.Lexeme + '!".');

  Result := Method.Bind(Obj);
end;

function TAstInterpreterVisitor.Visit(ThisExpression: TThisExpressionNode): TLoxValue;
begin
  Result := LookUpVariable(ThisExpression.Keyword, ThisExpression);
end;

function TAstInterpreterVisitor.Visit(SeTExpressionNode: TSeTExpressionNode): TLoxValue;
var
  Obj, Value: TLoxValue;
begin

  Obj := Evaluate(SeTExpressionNode.Obj);

  if not (Obj.ValueType = TLoxValueType.IS_OBJECT) then
    raise ELoxRuntimeError.Create(SeTExpressionNode.Name, 'Somente instâncias têm campos.');

  Value := Evaluate(SeTExpressionNode.Value);
  TLoxObjectInstance(Obj.ObjectInstanceValue).SetValue(SeTExpressionNode.Name, Value);

  Result := Value;

end;

function TAstInterpreterVisitor.Visit(GeTExpressionNode: TGeTExpressionNode): TLoxValue;
var
  Obj: TLoxValue;
begin
  Obj := Evaluate(GeTExpressionNode.Obj);

  if (Obj.ValueType = TLoxValueType.IS_OBJECT) then
  begin
    Result := TLoxObjectInstance(Obj.ObjectInstanceValue).GetValue(GeTExpressionNode.Name);
    Exit();
  end;

  raise ELoxRuntimeError.Create(GeTExpressionNode.Name, 'Somente instâncias têm propriedades.');
end;

function TAstInterpreterVisitor.Visit(ClassStatement: TClassStatementNode): TLoxValue;
var
  Value: TLoxValue;
  Methods: TDictionary<string, TCallableFunction>;
  Method: TFunctionStatementNode;
  Func: TCallableFunction;
  Superclass: TLoxValue;
begin
  Superclass := default(TLoxValue);
  Superclass.ValueType := TLoxValueType.IS_NULL;

  if Assigned(ClassStatement.Superclass) then
  begin
    Superclass := Evaluate(ClassStatement.Superclass);

    if not (Superclass.ValueType in [TLoxValueType.IS_CLASS, TLoxValueType.IS_OBJECT]) then
      raise ELoxRuntimeError.Create(ClassStatement.Superclass.Name, 'A superclasse deve ser uma classe.');
  end;

  Value := default(TLoxValue);
  Value.ValueType := TLoxValueType.IS_NULL;
  FEnvironment.Define(ClassStatement.Name.Lexeme, Value);

  if Assigned(ClassStatement.Superclass) then
  begin
    FEnvironment := TEnvironment.Create(FEnvironment);
    FEnvironment.Define('super', Superclass);
  end;

  Methods := TDictionary<string, TCallableFunction>.Create();

  for Method in ClassStatement.Methods do
  begin
    Func := TCallableFunction.Create(Method, FEnvironment, Method.Name.Lexeme = 'init');
    Methods.AddOrSetValue(Method.Name.Lexeme, Func);
  end;

  if Assigned(ClassStatement.Superclass) then
    FEnvironment := FEnvironment.Enclosing;

  Value := default(TLoxValue);
  Value.ValueType := TLoxValueType.IS_OBJECT;
  Value.ClassValue := TLoxClass.Create(ClassStatement.Name.Lexeme, Superclass, Methods);
  FEnvironment.Assign(ClassStatement.Name, Value);

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

function TAstInterpreterVisitor.Visit(ReturnStatement: TReturnStatementNode): TLoxValue;
var
  Value: TLoxValue;
begin
  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;

  if Assigned(ReturnStatement.Value) then
    Value := Evaluate(ReturnStatement.Value);

  raise EReturnException.Create(Value);
end;

function TAstInterpreterVisitor.Visit(FunctionStatement: TFunctionStatementNode): TLoxValue;
var
  FunctionValue: TLoxValue;
begin
  FunctionValue.ValueType := TLoxValueType.IS_CALLABLE;
  FunctionValue.CallableValue := TCallableFunction.Create(FunctionStatement, FEnvironment, false);

  FEnvironment.Define(FunctionStatement.Name.Lexeme, FunctionValue);

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

function TAstInterpreterVisitor.Visit(CallExpression: TCallExpressionNode): TLoxValue;
var
  Callee: TLoxValue;
  Arguments: TList<TLoxValue>;
  Argument: TExpressionNode;
  FuncValue: TCallable;
begin

  Callee := Evaluate(CallExpression.Callee);

  Arguments := TList<TLoxValue>.Create();

  for Argument in CallExpression.Arguments do
    Arguments.Add(Evaluate(Argument));

  if not (Callee.ValueType in [TLoxValueType.IS_CALLABLE, TLoxValueType.IS_CLASS, TLoxValueType.IS_OBJECT, TLoxValueType.IS_METHOD]) then
    raise ELoxRuntimeError.Create(CallExpression.paren, 'Somente é permitido chamar funções e classes.');

  FuncValue := TCallable(Callee.CallableValue);

  if not (Arguments.Count = FuncValue.Arity()) then
  begin
    raise ELoxRuntimeError.Create(CallExpression.paren, 'Experado ' + IntToStr(FuncValue.Arity()) + ' argumentos, mas tem ' + IntToStr(Arguments.Count) + '.');
  end;

  Result := FuncValue.Call(Self, Arguments);
end;

function TAstInterpreterVisitor.Visit(LogicalExpression: TLogicalExpressionNode): TLoxValue;
var
  left: TLoxValue;
begin
  left := Evaluate(LogicalExpression.left);

  if (LogicalExpression.Operador.TokenType = TLoxTokenType.OR_KEYWORD) then
  begin
    if IsTruthy(left) then
      Exit(left);
  end
  else if not IsTruthy(left) then
    Exit(left);

  Result := Evaluate(LogicalExpression.Right);
end;

function TAstInterpreterVisitor.Visit(VarStatement: TVarStatementNode): TLoxValue;
var
  Value: TLoxValue;
begin
  if (VarStatement.Initializer <> nil) then
    Value := Evaluate(VarStatement.Initializer)
  else
    Value.ValueType := TLoxValueType.IS_NULL;

  FEnvironment.Define(VarStatement.Name.Lexeme, Value);

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

function TAstInterpreterVisitor.Visit(IfStatement: TIfStatementNode): TLoxValue;
begin
  if (IsTruthy(Evaluate(IfStatement.Condition))) then
    Execute(IfStatement.ThenBranch)
  else if Assigned(IfStatement.ElseBranch) then
    Execute(IfStatement.ElseBranch);

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

function TAstInterpreterVisitor.Visit(BlockStatement: TBlockStatementNode): TLoxValue;
begin
  ExecuteBlock(BlockStatement.Statements, TEnvironment.Create(FEnvironment));

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

function TAstInterpreterVisitor.Visit(AssignExpression: TAssignExpressionNode): TLoxValue;
var
  Value: TLoxValue;
  Distance: Integer;
begin
  Value := Evaluate(AssignExpression.Value);

  if FLocals.TryGetValue(AssignExpression, Distance) then
    FEnvironment.AssignAt(Distance, AssignExpression.Name, Value)
  else
    FGlobals.Assign(AssignExpression.Name, Value);

  Result := Value;
end;

function TAstInterpreterVisitor.Visit(VariableExpression: TVariableExpressionNode): TLoxValue;
begin
  Result := LookUpVariable(VariableExpression.Name, VariableExpression)
end;

function TAstInterpreterVisitor.LookUpVariable(Name: TLoxToken; Expr: TExpressionNode): TLoxValue;
var
  Distance: Integer;
begin
  if FLocals.TryGetValue(Expr, Distance) then
    Result := FEnvironment.GetAt(Distance, Name.Lexeme)
  else
    Result := FGlobals.Get(Name);
end;

procedure RuntimeError(Error: ELoxRuntimeError);
begin
  Writeln(Error.Message + sLineBreak + '[Linha Nro: ' + IntToStr(Error.token.LineNro) + ']');
  HadRuntimeError := True;
end;

procedure TAstInterpreterVisitor.Execute(Statement: TStatementNode);
begin
  Statement.Accept(Self);
end;

procedure TAstInterpreterVisitor.Resolve(Expr: TExpressionNode; Depth: Integer);
begin
  FLocals.AddOrSetValue(Expr, Depth);
end;

procedure TAstInterpreterVisitor.ExecuteBlock(Statements: TObjectList<TStatementNode>; Environment: TEnvironment);
var
  PreviousEnvironment: TEnvironment;
  Statement: TStatementNode;
begin
  PreviousEnvironment := FEnvironment;

  try
    FEnvironment := Environment;

    for Statement in Statements do
      Execute(Statement);
  finally
    FEnvironment := PreviousEnvironment;
  end;

end;

procedure TAstInterpreterVisitor.Interpret(Statements: TObjectList<TStatementNode>);
var
  Statement: TStatementNode;
begin
  try
    HadRuntimeError := false;

    for Statement in Statements do
      Execute(Statement);

  except
    on E: ELoxRuntimeError do
      RuntimeError(E);
  end;
end;

function TAstInterpreterVisitor.Visit(PrintStatement: TPrintStatementNode): TLoxValue;
var
  Value: TLoxValue;
begin
  Value := Evaluate(PrintStatement.Expr);
  Writeln(Stringify(Value));

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

function TAstInterpreterVisitor.Visit(ExpressionStatement: TExpressionStatementNode): TLoxValue;
begin
  Evaluate(ExpressionStatement.Expression);

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

{ TClockFunction }

function TClockFunction.Arity: Integer;
begin
  Result := 0;
end;

function TClockFunction.Call(interpreter: TAstInterpreterVisitor; Arguments: TList<TLoxValue>): TLoxValue;
begin
  Result.ValueType := TLoxValueType.IS_INT32;
  Result.Int32Value := MillisecondOfTheDay(Now);
end;

function TClockFunction.ToString: string;
begin
  Result := '<native fn>';
end;

{ TCallableFunction }

function TCallableFunction.Arity: Integer;
begin
  Result := FDeclaration.Params.Count;
end;

function TCallableFunction.Call(interpreter: TAstInterpreterVisitor; Arguments: TList<TLoxValue>): TLoxValue;
var
  Environment: TEnvironment;
  i: Integer;
begin
  Environment := TEnvironment.Create(FClosure);

  for i := 0 to FDeclaration.Params.Count - 1 do
    Environment.Define(FDeclaration.Params[i].Lexeme, Arguments[i]);

  try
    interpreter.ExecuteBlock(FDeclaration.Body, Environment);
  except
    on ReturnException: EReturnException do
      if FIsInitializer then
      begin
        Result := FClosure.GetAt(0, 'this');
        Exit();
      end
      else
      begin
        Result := ReturnException.Value;
        Exit();
      end;
  end;

  if (FIsInitializer) then
    Exit(FClosure.GetAt(0, 'this'));

  Result := default(TLoxValue);
  Result.ValueType := TLoxValueType.IS_NULL;
end;

constructor TCallableFunction.Create(Declaration: TFunctionStatementNode; Closure: TEnvironment; IsInitializer: Boolean);
begin
  FDeclaration := Declaration;
  FClosure := Closure;
  FIsInitializer := IsInitializer;
end;

function TCallableFunction.Bind(Instance: TLoxObjectInstance): TLoxValue;
var
  Environment: TEnvironment;
  Value: TLoxValue;
begin
  Value := default(TLoxValue);
  Value.ValueType := TLoxValueType.IS_OBJECT;
  Value.ObjectInstanceValue := Instance;

  Environment := TEnvironment.Create(FClosure);
  Environment.Define('this', Value);

  Value := default(TLoxValue);
  Value.ValueType := TLoxValueType.IS_METHOD;
  Value.MethodValue := TCallableFunction.Create(FDeclaration, Environment, FIsInitializer);

  Result := Value;
end;

function TCallableFunction.ToString: string;
begin
  Result := '<fn ' + FDeclaration.Name.Lexeme + '>';
end;

{ EReturnException }

constructor EReturnException.Create(Value: TLoxValue);
begin
  inherited Create('');
  FValue := Value;
end;

{ TLoxClass }

function TLoxClass.Arity(): Integer;
var
  Initializer: TCallableFunction;
begin
  Initializer := FindMethod('init');
  if Assigned(Initializer) then
    Result := Initializer.Arity()
  else
    Result := 0;
end;

function TLoxClass.Call(Interpreter: TAstInterpreterVisitor; Arguments: TList<TLoxValue>): TLoxValue;
var
  ObjectValue: TLoxValue;
  Initializer: TCallableFunction;
begin
  ObjectValue := default(TLoxValue);
  ObjectValue.ValueType := TLoxValueType.IS_OBJECT;
  ObjectValue.ObjectInstanceValue := TLoxObjectInstance.Create(Self);

  Initializer := FindMethod('init');
  if Assigned(Initializer) then
    TCallableFunction(Initializer.Bind(ObjectValue.ObjectInstanceValue).MethodValue).Call(Interpreter, Arguments);

  Result := ObjectValue;
end;

constructor TLoxClass.Create(Name: string; Superclass: TLoxValue; Methods: TDictionary<string, TCallableFunction>);
begin
  FName := Name;
  FMethods := Methods;
  FSuperclass := Superclass;
end;

function TLoxClass.FindMethod(Name: string): TCallableFunction;
begin
  if (FMethods.ContainsKey(Name)) then
    Result := FMethods[Name]
  else if FSuperclass.ValueType in [TLoxValueType.IS_CLASS, TLoxValueType.IS_OBJECT] then
    Result := TLoxClass(FSuperclass.ClassValue).FindMethod(Name)
  else
    Result := nil;
end;

function TLoxClass.ToString: string;
begin
  Result := FName;
end;

{ TLoxObjectInstance }

constructor TLoxObjectInstance.Create(AClass: TLoxClass);
begin
  FClass := AClass;
  FFields := TDictionary<string, TLoxValue>.Create();
end;

function TLoxObjectInstance.ToString: string;
begin
  Result := FClass.Name + ' instance';
end;

function TLoxObjectInstance.GetValue(Name: TLoxToken): TLoxValue;
var
  Method: TCallableFunction;
begin
  if FFields.TryGetValue(Name.Lexeme, Result) then
    Exit();

  Method := FClass.FindMethod(Name.Lexeme);
  if Assigned(Method) then
  begin
    Result := Method.Bind(Self);
    Exit();
  end;

  raise ELoxRuntimeError.Create(Name, 'Propriedade indefinida "' + Name.Lexeme + '".');

end;

procedure TLoxObjectInstance.SetValue(Name: TLoxToken; Value: TLoxValue);
begin
  FFields.AddOrSetValue(Name.Lexeme, Value);
end;

end.

