program Hello;

{ The smallest program this compiler takes: the runtime library is read,
  one line is written, and the image built for it is the shape every other
  sample has. It is the reference for the image layout, the way the fixpoint
  chain is the reference for code generation.

  What it prints:

    hello     one line }

{ The runtime library is RTLDOS.PAS, and the compiler reads it before the
  first line of this file: there is no include for it here. }

begin
 WriteLn('hello, HX-DOS')
end.
