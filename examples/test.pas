program Test;

procedure x;
 procedure y;
 begin
  WriteLn('BLA');
 end;
begin
 y;
end;

var a,b:integer;
begin
 for a:=1 to 16 do begin
  for b:=16 downto 1 do begin
   WriteLn(a:5,b:5);
  end; 
 end;
 x;
end.