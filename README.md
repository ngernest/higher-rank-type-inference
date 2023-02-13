	Prototype implementation of type inference for higher-rank types
	~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

This is a small but complete implementation of type inference for higher-rank
types.  There are the following files:

  `Main.lhs`:	   Test harness

  `TcTerm.lhs`:	   The main type inference engine

  `TcMonad.lhs`:	   The type inference monad Tc (section 5.2)

  `BasicTypes.lhs`:   Data type declarations, for terms and types (section 5.1)

  `Parser.lhs`:	   A simple combinator parser



To get started: run `ghci Main.lhs` in the terminal

Type `tcs "\\x.x"` to type-check an expression written as a literal string, or
type `tcf "foo.test"` to type-check an expression in a file `foo.test`.