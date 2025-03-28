/*-----------------------------------------------------------------------

  SDCC.y - parser definition file for sdcc :
          Written By : Sandeep Dutta . sandeep.dutta@usa.net (1997)

   This program is free software; you can redistribute it and/or modify it
   under the terms of the GNU General Public License as published by the
   Free Software Foundation; either version 2, or (at your option) any
   later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

   In other words, you are welcome to use, share and improve this program.
   You are forbidden to forbid anyone else to use, share and improve
   what you give them.   Help stamp out software-hoarding!
-------------------------------------------------------------------------*/
%{
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "SDCCglobl.h"
#include "SDCCsymt.h"
#include "SDCChasht.h"
#include "SDCCval.h"
#include "SDCCmem.h"
#include "SDCCast.h"
#include "port.h"
#include "newalloc.h"
#include "SDCCerr.h"
#include "SDCCutil.h"

extern int yyerror (char *);
extern FILE     *yyin;
int NestLevel = 0 ;     /* current NestLevel       */
int stackPtr  = 1 ;     /* stack pointer           */
int xstackPtr = 0 ;     /* xstack pointer          */
int reentrant = 0 ;
int blockNo   = 0 ;     /* sequential block number  */
int currBlockno=0 ;
int inCritical= 0 ;
int seqPointNo= 1 ;     /* sequence point number */
int ignoreTypedefType=0;
extern int yylex();
int yyparse(void);
extern int noLineno ;
char lbuff[1024];      /* local buffer */

/* break & continue stacks */
STACK_DCL(continueStack  ,symbol *,MAX_NEST_LEVEL)
STACK_DCL(breakStack  ,symbol *,MAX_NEST_LEVEL)
STACK_DCL(forStack  ,symbol *,MAX_NEST_LEVEL)
STACK_DCL(swStk   ,ast   *,MAX_NEST_LEVEL)
STACK_DCL(blockNum,int,MAX_NEST_LEVEL*3)

value *cenum = NULL  ;  /* current enumeration  type chain*/
bool uselessDecl = TRUE;

#define YYDEBUG 1

%}
%expect 6

%union {
    symbol     *sym ;      /* symbol table pointer       */
    structdef  *sdef;      /* structure definition       */
    char       yychar[SDCC_NAME_MAX+1];
    sym_link   *lnk ;      /* declarator  or specifier   */
    int        yyint;      /* integer value returned     */
    value      *val ;      /* for integer constant       */
    initList   *ilist;     /* initial list               */
    designation*dsgn;      /* designator                 */
    const char *yyinline;  /* inlined assembler code     */
    ast        *asts;      /* expression tree            */
}

%token <yychar> IDENTIFIER TYPE_NAME
%token <val> CONSTANT STRING_LITERAL
%token SIZEOF TYPEOF OFFSETOF
%token PTR_OP INC_OP DEC_OP LEFT_OP RIGHT_OP LE_OP GE_OP EQ_OP NE_OP
%token AND_OP OR_OP
%token <yyint> MUL_ASSIGN DIV_ASSIGN MOD_ASSIGN ADD_ASSIGN
%token <yyint> SUB_ASSIGN LEFT_ASSIGN RIGHT_ASSIGN AND_ASSIGN
%token <yyint> XOR_ASSIGN OR_ASSIGN
%token TYPEDEF EXTERN STATIC AUTO REGISTER CODE EEPROM INTERRUPT SFR SFR16 SFR32
%token AT SBIT REENTRANT USING  XDATA DATA IDATA PDATA VAR_ARGS CRITICAL
%token NONBANKED BANKED SHADOWREGS SD_WPARAM
%token SD_BOOL SD_CHAR SD_SHORT SD_INT SD_LONG SIGNED UNSIGNED SD_FLOAT DOUBLE FIXED16X16 SD_CONST VOLATILE SD_VOID BIT
%token STRUCT UNION ENUM RANGE SD_FAR
%token CASE DEFAULT IF ELSE SWITCH WHILE DO FOR GOTO CONTINUE BREAK RETURN
%token NAKED JAVANATIVE OVERLAY
%token <yyinline> INLINEASM
%token IFX ADDRESS_OF GET_VALUE_AT_ADDRESS SPIL UNSPIL GETHBIT GETABIT GETBYTE GETWORD
%token BITWISEAND UNARYMINUS IPUSH IPOP PCALL  ENDFUNCTION JUMPTABLE
%token RRC RLC
%token CAST CALL PARAM NULLOP BLOCK LABEL RECEIVE SEND ARRAYINIT
%token DUMMY_READ_VOLATILE ENDCRITICAL SWAP INLINE RESTRICT SMALLC

%type <yyint> Interrupt_storage
%type <sym> identifier declarator declarator2 declarator3 enumerator_list enumerator
%type <sym> struct_declarator function_declarator function_declarator2
%type <sym> struct_declarator_list struct_declaration struct_declaration_list
%type <sym> declaration init_declarator_list init_declarator
%type <sym> declaration_list identifier_list
%type <sym> declarator2_function_attributes while do for critical
%type <lnk> pointer type_specifier_list type_specifier_list_ type_specifier type_name
%type <lnk> storage_class_specifier struct_or_union_specifier function_specifier
%type <lnk> declaration_specifiers declaration_specifiers_ sfr_reg_bit sfr_attributes
%type <lnk> function_attribute function_attributes enum_specifier
%type <lnk> abstract_declarator abstract_declarator2 unqualified_pointer
%type <val> parameter_type_list parameter_list parameter_declaration opt_assign_expr
%type <sdef> stag opt_stag
%type <asts> primary_expr
%type <asts> postfix_expr unary_expr offsetof_member_designator cast_expr multiplicative_expr
%type <asts> additive_expr shift_expr relational_expr equality_expr
%type <asts> and_expr exclusive_or_expr inclusive_or_expr logical_or_expr
%type <asts> logical_and_expr conditional_expr assignment_expr constant_expr
%type <asts> expr argument_expr_list function_definition expr_opt
%type <asts> statement_list statement labeled_statement compound_statement
%type <asts> expression_statement selection_statement iteration_statement
%type <asts> jump_statement function_body else_statement string_literal
%type <asts> critical_statement
%type <dsgn> designator designator_list designation designation_opt
%type <ilist> initializer initializer_list
%type <yyint> unary_operator assignment_operator struct_or_union

%start file

%%

file
   : /* empty */
        { if (!options.lessPedantic)
                    werror(W_EMPTY_SOURCE_FILE);
        }
   | program
   ;

program
   : external_definition
   | program external_definition
   ;

external_definition
   : function_definition     {
                               blockNo=0;
                             }
   | declaration             {
                               ignoreTypedefType = 0;
                               if ($1 && $1->type
                                && IS_FUNC($1->type))
                               {
                                   /* The only legal storage classes for
                                    * a function prototype (declaration)
                                    * are extern and static. extern is the
                                    * default. Thus, if this function isn't
                                    * explicitly marked static, mark it
                                    * extern.
                                    */
                                   if ($1->etype
                                    && IS_SPEC($1->etype)
                                    && !SPEC_STAT($1->etype))
                                   {
                                        SPEC_EXTR($1->etype) = 1;
                                   }
                               }
                               addSymChain (&$1);
                               allocVariables ($1) ;
                               cleanUpLevel (SymbolTab,1);
                             }
   ;

function_definition
   : function_declarator function_body  {   /* function type not specified */
                                   /* assume it to be 'int'       */
                                   addDecl($1,0,newIntLink());
                                   $$ = createFunction($1,$2);
                               }
   | declaration_specifiers function_declarator function_body
                                {
                                    pointerTypes($2->type,copyLinkChain($1));
                                    addDecl($2,0,$1);
                                    $$ = createFunction($2,$3);
                                }
   ;

function_attribute
   : function_attributes
   | function_attributes function_attribute { $$ = mergeSpec($1,$2,"function_attribute"); }
   ;

function_attributes
   :  USING constant_expr {
                        $$ = newLink(SPECIFIER) ;
                        FUNC_REGBANK($$) = (int) ulFromVal(constExprValue($2,TRUE));
                     }
   |  REENTRANT      {  $$ = newLink (SPECIFIER);
                        FUNC_ISREENT($$)=1;
                     }
   |  CRITICAL       {  $$ = newLink (SPECIFIER);
                        FUNC_ISCRITICAL($$) = 1;
                     }
   |  NAKED          {  $$ = newLink (SPECIFIER);
                        FUNC_ISNAKED($$)=1;
                     }
   |  JAVANATIVE     {  $$ = newLink (SPECIFIER);
                        FUNC_ISJAVANATIVE($$)=1;
                     }
   |  OVERLAY        {  $$ = newLink (SPECIFIER);
                        FUNC_ISOVERLAY($$)=1;
                     }
   |  NONBANKED      {$$ = newLink (SPECIFIER);
                        FUNC_NONBANKED($$) = 1;
                        if (FUNC_BANKED($$)) {
                            werror(W_BANKED_WITH_NONBANKED);
                        }
                     }
   |  SHADOWREGS     {$$ = newLink (SPECIFIER);
                        FUNC_ISSHADOWREGS($$) = 1;
                     }
   |  SD_WPARAM      {$$ = newLink (SPECIFIER);
                        FUNC_ISWPARAM($$) = 1;
                     }
   |  BANKED         {$$ = newLink (SPECIFIER);
                        FUNC_BANKED($$) = 1;
                        if (FUNC_NONBANKED($$)) {
                            werror(W_BANKED_WITH_NONBANKED);
                        }
                     }
   |  Interrupt_storage
                     {
                        $$ = newLink (SPECIFIER) ;
                        FUNC_INTNO($$) = $1 ;
                        FUNC_ISISR($$) = 1;
                     }
   |  SMALLC         {  $$ = newLink (SPECIFIER);
                        FUNC_ISSMALLC($$)=1;
                     }
   ;

function_body
   : compound_statement
   | declaration_list compound_statement
                     {
                       werror (E_OLD_STYLE, ($1 ? $1->name: "")) ;
                       exit (1);
                     }
   ;

offsetof_member_designator
   : identifier      { $$ = newAst_VALUE (symbolVal ($1)); }
   | offsetof_member_designator '.' { ignoreTypedefType = 1; } identifier
                     {
                       ignoreTypedefType = 0;
                       $4 = newSymbol ($4->name, NestLevel);
                       $4->implicit = 1;
                       $$ = newNode ('.', $1, newAst_VALUE (symbolVal ($4))) ;
                     }
   | offsetof_member_designator '[' expr ']'
                     {
                       $$ = newNode ('[', $1, $3);
                     }
   ;

primary_expr
   : identifier      { $$ = newAst_VALUE (symbolVal ($1)); }
   | CONSTANT        { $$ = newAst_VALUE ($1); }
   | string_literal
   | '(' expr ')'    { $$ = $2; }
   ;

string_literal
    : STRING_LITERAL                    { $$ = newAst_VALUE($1); }
    ;

postfix_expr
   : primary_expr
   | postfix_expr '[' expr ']'          { $$ = newNode  ('[', $1, $3) ; }
   | postfix_expr '(' ')'               { $$ = newNode  (CALL,$1,NULL);
                                          $$->left->funcName = 1;}
   | postfix_expr '(' argument_expr_list ')'
          {
            $$ = newNode  (CALL,$1,$3) ; $$->left->funcName = 1;
          }
   | postfix_expr '.' { ignoreTypedefType = 1; } identifier
                      {
                        ignoreTypedefType = 0;
                        $4 = newSymbol($4->name,NestLevel);
                        $4->implicit = 1;
                        $$ = newNode(PTR_OP,newNode('&',$1,NULL),newAst_VALUE(symbolVal($4)));
                      }
   | postfix_expr PTR_OP { ignoreTypedefType = 1; } identifier
                      {
                        ignoreTypedefType = 0;
                        $4 = newSymbol($4->name,NestLevel);
                        $4->implicit = 1;
                        $$ = newNode(PTR_OP,$1,newAst_VALUE(symbolVal($4)));
                      }
   | postfix_expr INC_OP
                      { $$ = newNode(INC_OP,$1,NULL);}
   | postfix_expr DEC_OP
                      { $$ = newNode(DEC_OP,$1,NULL); }
   ;

argument_expr_list
   : assignment_expr
   | assignment_expr ',' argument_expr_list { $$ = newNode(PARAM,$1,$3); }
   ;

unary_expr
   : postfix_expr
   | INC_OP unary_expr        { $$ = newNode (INC_OP, NULL, $2); }
   | DEC_OP unary_expr        { $$ = newNode (DEC_OP, NULL, $2); }
   | unary_operator cast_expr { $$ = newNode ($1, $2, NULL); }
   | SIZEOF unary_expr        { $$ = newNode (SIZEOF, NULL, $2); }
   | SIZEOF '(' type_name ')' { $$ = newAst_VALUE (sizeofOp ($3)); }
   | TYPEOF unary_expr        { $$ = newNode (TYPEOF, NULL, $2); }
   | OFFSETOF '(' type_name ',' offsetof_member_designator ')' { $$ = offsetofOp($3, $5); }
   ;

unary_operator
   : '&'    { $$ = '&' ;}
   | '*'    { $$ = '*' ;}
   | '+'    { $$ = '+' ;}
   | '-'    { $$ = '-' ;}
   | '~'    { $$ = '~' ;}
   | '!'    { $$ = '!' ;}
   ;

cast_expr
   : unary_expr
   | '(' type_name ')' cast_expr { $$ = newNode(CAST,newAst_LINK($2),$4); }
   ;

multiplicative_expr
   : cast_expr
   | multiplicative_expr '*' cast_expr { $$ = newNode('*',$1,$3);}
   | multiplicative_expr '/' cast_expr { $$ = newNode('/',$1,$3);}
   | multiplicative_expr '%' cast_expr { $$ = newNode('%',$1,$3);}
   ;

additive_expr
   : multiplicative_expr
   | additive_expr '+' multiplicative_expr { $$=newNode('+',$1,$3);}
   | additive_expr '-' multiplicative_expr { $$=newNode('-',$1,$3);}
   ;

shift_expr
   : additive_expr
   | shift_expr LEFT_OP additive_expr  { $$ = newNode(LEFT_OP,$1,$3); }
   | shift_expr RIGHT_OP additive_expr { $$ = newNode(RIGHT_OP,$1,$3); }
   ;

relational_expr
   : shift_expr
   | relational_expr '<' shift_expr   { $$ = newNode('<',  $1,$3);}
   | relational_expr '>' shift_expr   { $$ = newNode('>',  $1,$3);}
   | relational_expr LE_OP shift_expr { $$ = newNode(LE_OP,$1,$3);}
   | relational_expr GE_OP shift_expr { $$ = newNode(GE_OP,$1,$3);}
   ;

equality_expr
   : relational_expr
   | equality_expr EQ_OP relational_expr { $$ = newNode(EQ_OP,$1,$3);}
   | equality_expr NE_OP relational_expr { $$ = newNode(NE_OP,$1,$3);}
   ;

and_expr
   : equality_expr
   | and_expr '&' equality_expr  { $$ = newNode('&',$1,$3);}
   ;

exclusive_or_expr
   : and_expr
   | exclusive_or_expr '^' and_expr { $$ = newNode('^',$1,$3);}
   ;

inclusive_or_expr
   : exclusive_or_expr
   | inclusive_or_expr '|' exclusive_or_expr { $$ = newNode('|',$1,$3);}
   ;

logical_and_expr
   : inclusive_or_expr
   | logical_and_expr AND_OP { seqPointNo++;} inclusive_or_expr
                                 { $$ = newNode(AND_OP,$1,$4);}
   ;

logical_or_expr
   : logical_and_expr
   | logical_or_expr OR_OP { seqPointNo++;} logical_and_expr
                                 { $$ = newNode(OR_OP,$1,$4); }
   ;

conditional_expr
   : logical_or_expr
   | logical_or_expr '?' { seqPointNo++;} logical_or_expr ':' conditional_expr
                     {
                        $$ = newNode(':',$4,$6) ;
                        $$ = newNode('?',$1,$$) ;
                     }
   ;

assignment_expr
   : conditional_expr
   | cast_expr assignment_operator assignment_expr
                     {

                             switch ($2) {
                             case '=':
                                     $$ = newNode($2,$1,$3);
                                     break;
                             case MUL_ASSIGN:
                                     $$ = createRMW($1, '*', $3);
                                     break;
                             case DIV_ASSIGN:
                                     $$ = createRMW($1, '/', $3);
                                     break;
                             case MOD_ASSIGN:
                                     $$ = createRMW($1, '%', $3);
                                     break;
                             case ADD_ASSIGN:
                                     $$ = createRMW($1, '+', $3);
                                     break;
                             case SUB_ASSIGN:
                                     $$ = createRMW($1, '-', $3);
                                     break;
                             case LEFT_ASSIGN:
                                     $$ = createRMW($1, LEFT_OP, $3);
                                     break;
                             case RIGHT_ASSIGN:
                                     $$ = createRMW($1, RIGHT_OP, $3);
                                     break;
                             case AND_ASSIGN:
                                     $$ = createRMW($1, '&', $3);
                                     break;
                             case XOR_ASSIGN:
                                     $$ = createRMW($1, '^', $3);
                                     break;
                             case OR_ASSIGN:
                                     $$ = createRMW($1, '|', $3);
                                     break;
                             default :
                                     $$ = NULL;
                             }

                     }
;

assignment_operator
   : '='             { $$ = '=' ;}
   | MUL_ASSIGN
   | DIV_ASSIGN
   | MOD_ASSIGN
   | ADD_ASSIGN
   | SUB_ASSIGN
   | LEFT_ASSIGN
   | RIGHT_ASSIGN
   | AND_ASSIGN
   | XOR_ASSIGN
   | OR_ASSIGN
   ;

expr
   : assignment_expr
   | expr ',' { seqPointNo++;} assignment_expr { $$ = newNode(',',$1,$4);}
   ;

constant_expr
   : conditional_expr
   ;

declaration
   : declaration_specifiers ';'
      {
         if (uselessDecl)
           werror(W_USELESS_DECL);
         uselessDecl = TRUE;
         $$ = NULL ;
      }
   | declaration_specifiers init_declarator_list ';'
      {
         /* add the specifier list to the id */
         symbol *sym , *sym1;

         for (sym1 = sym = reverseSyms($2);sym != NULL;sym = sym->next) {
             sym_link *lnk = copyLinkChain($1);
             /* do the pointer stuff */
             pointerTypes(sym->type,lnk);
             addDecl (sym,0,lnk) ;
         }

         uselessDecl = TRUE;
         $$ = sym1 ;
      }
   ;

declaration_specifiers : declaration_specifiers_ { $$ = finalizeSpec($1); } ;

declaration_specifiers_
   : storage_class_specifier                                            { $$ = $1; }
   | storage_class_specifier declaration_specifiers_ {
     /* if the decl $2 is not a specifier */
     /* find the spec and replace it      */
     $$ = mergeDeclSpec($1, $2, "storage_class_specifier declaration_specifiers - skipped");
   }
   | type_specifier                                 { $$ = $1; }
   | type_specifier declaration_specifiers_         {
     /* if the decl $2 is not a specifier */
     /* find the spec and replace it      */
     $$ = mergeDeclSpec($1, $2, "type_specifier declaration_specifiers - skipped");
   }
   | function_specifier                             { $$ = $1; }
   | function_specifier declaration_specifiers_     {
     /* if the decl $2 is not a specifier */
     /* find the spec and replace it      */
     $$ = mergeDeclSpec($1, $2, "function_specifier declaration_specifiers - skipped");
   }
   ;

init_declarator_list
   : init_declarator
   | init_declarator_list ',' init_declarator      { $3->next = $1 ; $$ = $3;}
   ;

init_declarator
   : declarator                  { $1->ival = NULL ; }
   | declarator '=' initializer  { $1->ival = $3   ; }
   ;

designation_opt
   :                             { $$ = NULL; }
   | designation
   ;

designation
   : designator_list '='         { $$ = revDesignation($1); }
   ;

designator_list
   : designator
   | designator_list designator  { $2->next = $1; $$ = $2; }
   ;

designator
   : '[' constant_expr ']'
         {
            value *tval;
            int elemno;

            tval = constExprValue($2, TRUE);
            /* if it is not a constant then Error  */
            if (!tval || (SPEC_SCLS(tval->etype) != S_LITERAL))
              {
                werror (E_CONST_EXPECTED);
                elemno = 0; /* arbitrary fixup */
              }
            else
              {
                if ((elemno = (int) ulFromVal(tval)) < 0)
                  {
                    werror (E_BAD_DESIGNATOR);
                    elemno = 0; /* arbitrary fixup */
                  }
              }
            $$ = newDesignation(DESIGNATOR_ARRAY, &elemno);
         }
   | '.' identifier              { $$ = newDesignation(DESIGNATOR_STRUCT,$2); }
   ;

storage_class_specifier
   : TYPEDEF   {
                  $$ = newLink (SPECIFIER) ;
                  SPEC_TYPEDEF($$) = 1 ;
               }
   | EXTERN    {
                  $$ = newLink(SPECIFIER);
                  SPEC_EXTR($$) = 1 ;
               }
   | STATIC    {
                  $$ = newLink (SPECIFIER);
                  SPEC_STAT($$) = 1 ;
               }
   | AUTO      {
                  $$ = newLink (SPECIFIER) ;
                  SPEC_SCLS($$) = S_AUTO  ;
               }
   | REGISTER  {
                  $$ = newLink (SPECIFIER);
                  SPEC_SCLS($$) = S_REGISTER ;
               }
   ;

function_specifier
   : INLINE    {
                  $$ = newLink (SPECIFIER) ;
                  SPEC_INLINE($$) = 1 ;
               }
   ;

Interrupt_storage
   : INTERRUPT { $$ = INTNO_UNSPEC ; }
   | INTERRUPT constant_expr
        { int intno = (int) ulFromVal(constExprValue($2,TRUE));
          if ((intno >= 0) && (intno <= INTNO_MAX))
            $$ = intno;
          else
            {
              werror(E_INT_BAD_INTNO, intno);
              $$ = INTNO_UNSPEC;
            }
        }
   ;

type_specifier
   : SD_BOOL   {
                  $$=newLink(SPECIFIER);
                  SPEC_NOUN($$) = V_BOOL   ;
                  ignoreTypedefType = 1;
               }
   | SD_CHAR   {
                  $$=newLink(SPECIFIER);
                  SPEC_NOUN($$) = V_CHAR  ;
                  ignoreTypedefType = 1;
               }
   | SD_SHORT  {
                  $$=newLink(SPECIFIER);
                  SPEC_SHORT($$) = 1 ;
                  ignoreTypedefType = 1;
               }
   | SD_INT    {
                  $$=newLink(SPECIFIER);
                  SPEC_NOUN($$) = V_INT   ;
                  ignoreTypedefType = 1;
               }
   | SD_LONG   {
                  $$=newLink(SPECIFIER);
                  SPEC_LONG($$) = 1       ;
                  ignoreTypedefType = 1;
               }
   | SIGNED    {
                  $$=newLink(SPECIFIER);
                  $$->select.s.b_signed = 1;
                  ignoreTypedefType = 1;
               }
   | UNSIGNED  {
                  $$=newLink(SPECIFIER);
                  SPEC_USIGN($$) = 1      ;
                  ignoreTypedefType = 1;
               }
   | SD_VOID   {
                  $$=newLink(SPECIFIER);
                  SPEC_NOUN($$) = V_VOID  ;
                  ignoreTypedefType = 1;
               }
   | SD_CONST  {
                  $$=newLink(SPECIFIER);
                  SPEC_CONST($$) = 1;
               }
   | VOLATILE  {
                  $$=newLink(SPECIFIER);
                  SPEC_VOLATILE($$) = 1 ;
               }
   | RESTRICT  {
                  $$=newLink(SPECIFIER);
                  SPEC_RESTRICT($$) = 1 ;
               }
   | SD_FLOAT  {
                  $$=newLink(SPECIFIER);
                  SPEC_NOUN($$) = V_FLOAT;
                  ignoreTypedefType = 1;
               }
   | FIXED16X16 {
                  $$=newLink(SPECIFIER);
                  SPEC_NOUN($$) = V_FIXED16X16;
                  ignoreTypedefType = 1;
               }
   | XDATA     {
                  $$ = newLink (SPECIFIER);
                  SPEC_SCLS($$) = S_XDATA  ;
               }
   | CODE      {
                  $$ = newLink (SPECIFIER) ;
                  SPEC_SCLS($$) = S_CODE ;
               }
   | EEPROM    {
                  $$ = newLink (SPECIFIER) ;
                  SPEC_SCLS($$) = S_EEPROM ;
               }
   | DATA      {
                  $$ = newLink (SPECIFIER);
                  SPEC_SCLS($$) = S_DATA   ;
               }
   | IDATA     {
                  $$ = newLink (SPECIFIER);
                  SPEC_SCLS($$) = S_IDATA  ;
               }
   | PDATA     {
                  $$ = newLink (SPECIFIER);
                  SPEC_SCLS($$) = S_PDATA  ;
               }
   | BIT       {
                  $$=newLink(SPECIFIER);
                  SPEC_NOUN($$) = V_BIT   ;
                  SPEC_SCLS($$) = S_BIT   ;
                  SPEC_BLEN($$) = 1;
                  SPEC_BSTR($$) = 0;
                  ignoreTypedefType = 1;
               }

   | AT constant_expr {
                  $$=newLink(SPECIFIER);
                  /* add this to the storage class specifier  */
                  SPEC_ABSA($$) = 1;   /* set the absolute addr flag */
                  /* now get the abs addr from value */
                  SPEC_ADDR($$) = (unsigned int) ulFromVal(constExprValue($2,TRUE)) ;
               }

   | struct_or_union_specifier  {
                                   uselessDecl = FALSE;
                                   $$ = $1 ;
                                   ignoreTypedefType = 1;
                                }
   | enum_specifier     {
                           cenum = NULL ;
                           uselessDecl = FALSE;
                           ignoreTypedefType = 1;
                           $$ = $1 ;
                        }
   | TYPE_NAME
         {
            symbol *sym;
            sym_link   *p  ;
            sym = findSym(TypedefTab,NULL,$1) ;
            $$ = p = copyLinkChain(sym ? sym->type : NULL);
            SPEC_TYPEDEF(getSpec(p)) = 0;
            ignoreTypedefType = 1;
         }
   | sfr_reg_bit
   ;

sfr_reg_bit
   :  SBIT  {
               $$ = newLink(SPECIFIER) ;
               SPEC_NOUN($$) = V_SBIT;
               SPEC_SCLS($$) = S_SBIT;
               SPEC_BLEN($$) = 1;
               SPEC_BSTR($$) = 0;
               ignoreTypedefType = 1;
            }
   |  sfr_attributes
   ;

sfr_attributes
   : SFR    {
               $$ = newLink(SPECIFIER) ;
               FUNC_REGBANK($$) = 0;
               SPEC_NOUN($$)    = V_CHAR;
               SPEC_SCLS($$)    = S_SFR ;
               SPEC_USIGN($$)   = 1 ;
               ignoreTypedefType = 1;
            }
   | SFR BANKED {
               $$ = newLink(SPECIFIER) ;
               FUNC_REGBANK($$) = 1;
               SPEC_NOUN($$)    = V_CHAR;
               SPEC_SCLS($$)    = S_SFR ;
               SPEC_USIGN($$)   = 1 ;
               ignoreTypedefType = 1;
            }
   ;

sfr_attributes
   : SFR16  {
               $$ = newLink(SPECIFIER) ;
               FUNC_REGBANK($$) = 0;
               SPEC_NOUN($$)    = V_INT;
               SPEC_SCLS($$)    = S_SFR;
               SPEC_USIGN($$)   = 1 ;
               ignoreTypedefType = 1;
            }
   ;

sfr_attributes
   : SFR32  {
               $$ = newLink(SPECIFIER) ;
               FUNC_REGBANK($$) = 0;
               SPEC_NOUN($$)    = V_INT;
               SPEC_SCLS($$)    = S_SFR;
               SPEC_LONG($$)    = 1;
               SPEC_USIGN($$)   = 1;
               ignoreTypedefType = 1;
            }
   ;

struct_or_union_specifier
   : struct_or_union opt_stag
        {
           if (!$2->type)
             {
               $2->type = $1;
             }
           else
             {
               if ($2->type != $1)
                 werror(E_BAD_TAG, $2->tag, $1==STRUCT ? "struct" : "union");
             }

        }
           '{' struct_declaration_list '}'
        {
           structdef *sdef ;
           symbol *sym, *dsym;

           // check for errors in structure members
           for (sym=$5; sym; sym=sym->next) {
             if (IS_ABSOLUTE(sym->etype)) {
               werrorfl(sym->fileDef, sym->lineDef, E_NOT_ALLOWED, "'at'");
               SPEC_ABSA(sym->etype) = 0;
             }
             if (IS_SPEC(sym->etype) && SPEC_SCLS(sym->etype)) {
               werrorfl(sym->fileDef, sym->lineDef, E_NOT_ALLOWED, "storage class");
               printTypeChainRaw (sym->type,NULL);
               SPEC_SCLS(sym->etype) = 0;
             }
             for (dsym=sym->next; dsym; dsym=dsym->next) {
               if (*dsym->name && strcmp(sym->name, dsym->name)==0) {
                 werrorfl(sym->fileDef, sym->lineDef, E_DUPLICATE_MEMBER,
                        $1==STRUCT ? "struct" : "union", sym->name);
                 werrorfl(dsym->fileDef, dsym->lineDef, E_PREVIOUS_DEF);
               }
             }
           }

           /* Create a structdef   */
           sdef = $2 ;
           sdef->fields   = reverseSyms($5) ;   /* link the fields */
           sdef->size  = compStructSize($1,sdef);   /* update size of  */
           promoteAnonStructs ($1, sdef);

           /* Create the specifier */
           $$ = newLink (SPECIFIER) ;
           SPEC_NOUN($$) = V_STRUCT;
           SPEC_STRUCT($$)= sdef ;
        }
   | struct_or_union stag
         {
            $$ = newLink(SPECIFIER) ;
            SPEC_NOUN($$) = V_STRUCT;
            SPEC_STRUCT($$) = $2;

           if (!$2->type)
             {
               $2->type = $1;
             }
           else
             {
               if ($2->type != $1)
                 werror(E_BAD_TAG, $2->tag, $1==STRUCT ? "struct" : "union");
             }
         }
   ;

struct_or_union
   : STRUCT          { $$ = STRUCT ; ignoreTypedefType = 1; }
   | UNION           { $$ = UNION  ; ignoreTypedefType = 1; }
   ;

opt_stag
: stag
|  {  /* synthesize a name add to structtable */
     ignoreTypedefType = 0;
     $$ = newStruct(genSymName(NestLevel)) ;
     $$->level = NestLevel ;
     addSym (StructTab, $$, $$->tag, $$->level, currBlockno, 0);
};

stag
:  identifier  {  /* add name to structure table */
     ignoreTypedefType = 0;
     $$ = findSymWithBlock (StructTab, $1, currBlockno);
     if (! $$ ) {
       $$ = newStruct($1->name) ;
       $$->level = NestLevel ;
       addSym (StructTab, $$, $$->tag, $$->level, currBlockno, 0);
     }
};


struct_declaration_list
   : struct_declaration
   | struct_declaration_list struct_declaration
       {
           symbol *sym=$2;

           /* go to the end of the chain */
           while (sym->next) sym=sym->next;
           sym->next = $1 ;

           $$ = $2;
       }
   ;

struct_declaration
   : type_specifier_list struct_declarator_list ';'
       {
           /* add this type to all the symbols */
           symbol *sym ;
           for ( sym = $2 ; sym != NULL ; sym = sym->next ) {
               sym_link *btype = copyLinkChain($1);

               /* make the symbol one level up */
               sym->level-- ;

               pointerTypes(sym->type,btype);
               if (!sym->type) {
                   sym->type = btype;
                   sym->etype = getSpec(sym->type);
               }
               else
                 addDecl (sym,0,btype);
               /* make sure the type is complete and sane */
               checkTypeSanity(sym->etype, sym->name);
           }
           ignoreTypedefType = 0;
           $$ = $2;
       }
   ;

struct_declarator_list
   : struct_declarator
   | struct_declarator_list ',' struct_declarator
       {
           $3->next  = $1 ;
           $$ = $3 ;
       }
   ;

struct_declarator
   : declarator
   | ':' constant_expr  {
                           unsigned int bitsize;
                           $$ = newSymbol (genSymName(NestLevel),NestLevel) ;
                           bitsize = (unsigned int) ulFromVal(constExprValue($2,TRUE));
                           if (bitsize > (port->s.int_size * 8)) {
                             bitsize = port->s.int_size * 8;
                             werror(E_BITFLD_SIZE, bitsize);
                           }
                           if (!bitsize)
                             bitsize = BITVAR_PAD;
                           $$->bitVar = bitsize;
                           $$->bitUnnamed = 1;
                        }
   | declarator ':' constant_expr
                        {
                          unsigned int bitsize;
                          bitsize = (unsigned int) ulFromVal(constExprValue($3,TRUE));
                          if (bitsize > (port->s.int_size * 8)) {
                            bitsize = port->s.int_size * 8;
                            werror(E_BITFLD_SIZE, bitsize);
                          }
                          if (!bitsize) {
                            $$ = newSymbol (genSymName(NestLevel),NestLevel) ;
                            $$->bitVar = BITVAR_PAD;
                            werror(W_BITFLD_NAMED);
                          }
                          else
                            $1->bitVar = bitsize;
                        }
   | { $$ = newSymbol ("", NestLevel) ; }

   ;

enum_specifier
   : ENUM            '{' enumerator_list '}' {
           $$ = newEnumType ($3);       //copyLinkChain(cenum->type);
           SPEC_SCLS(getSpec($$)) = 0;
         }

   | ENUM identifier '{' enumerator_list '}' {
     symbol *csym ;
     sym_link *enumtype;

     csym=findSym(enumTab,$2,$2->name);
     if ((csym && csym->level == $2->level))
       {
         werrorfl($2->fileDef, $2->lineDef, E_DUPLICATE_TYPEDEF,csym->name);
         werrorfl(csym->fileDef, csym->lineDef, E_PREVIOUS_DEF);
       }

     enumtype = newEnumType ($4);       //copyLinkChain(cenum->type);
     SPEC_SCLS(getSpec(enumtype)) = 0;
     $2->type = enumtype;

     /* add this to the enumerator table */
     if (!csym)
       addSym ( enumTab,$2,$2->name,$2->level,$2->block, 0);
     $$ = copyLinkChain(enumtype);
   }
   | ENUM identifier                         {
     symbol *csym ;

     /* check the enumerator table */
     if ((csym = findSym(enumTab,$2,$2->name)))
       $$ = copyLinkChain(csym->type);
     else  {
       $$ = newLink(SPECIFIER) ;
       SPEC_NOUN($$) = V_INT   ;
     }
   }
   ;

enumerator_list
    : enumerator
    | enumerator_list ','
    | enumerator_list ',' enumerator
      {
        $3->next = $1 ;
        $$ = $3  ;
      }
    ;

enumerator
    : identifier opt_assign_expr
      {
        symbol *sym;

        /* make the symbol one level up */
        $1->level-- ;
        // check if the symbol at the same level already exists
        if ((sym = findSymWithLevel (SymbolTab, $1)) &&
          sym->level == $1->level)
          {
            werrorfl ($1->fileDef, $1->lineDef, E_DUPLICATE_MEMBER, "enum", $1->name);
            werrorfl (sym->fileDef, sym->lineDef, E_PREVIOUS_DEF);
          }
        $1->type = copyLinkChain ($2->type);
        $1->etype= getSpec ($1->type);
        SPEC_ENUM ($1->etype) = 1;
        $$ = $1 ;
        // do this now, so we can use it for the next enums in the list
        addSymChain (&$1);
      }
    ;

opt_assign_expr
   :  '='   constant_expr  {
                              value *val ;

                              val = constExprValue($2,TRUE);
                              if (!IS_INT(val->type) && !IS_CHAR(val->type) && !IS_BOOL(val->type))
                                {
                                  werror(E_ENUM_NON_INTEGER);
                                  SNPRINTF(lbuff, sizeof(lbuff),
                                          "%d", (int) ulFromVal(val));
                                  val = constVal(lbuff);
                                }
                              $$ = cenum = val ;
                           }
   |                       {
                              if (cenum)  {
                                 SNPRINTF(lbuff, sizeof(lbuff),
                                          "%d", (int) ulFromVal(cenum)+1);
                                 $$ = cenum = constVal(lbuff);
                              }
                              else {
                                 $$ = cenum = constCharVal(0);
                              }
                           }
   ;

declarator
   : declarator3                        { $$ = $1 ; }
   | pointer declarator3
         {
             addDecl ($2,0,reverseLink($1));
             $$ = $2 ;
         }
   ;

declarator3
   : declarator2_function_attributes    { $$ = $1 ; }
   | declarator2                        { $$ = $1 ; }
   ;

function_declarator
   : declarator2_function_attributes    { $$ = $1; }
   | pointer declarator2_function_attributes
         {
             addDecl ($2,0,reverseLink($1));
             $$ = $2 ;
         }
   ;

declarator2_function_attributes
   : function_declarator2                 { $$ = $1 ; }
   | function_declarator2 function_attribute  {
           // copy the functionAttributes (not the args and hasVargs !!)
           struct value *args;
           unsigned hasVargs;
           sym_link *funcType=$1->type;

           while (funcType && !IS_FUNC(funcType))
             funcType = funcType->next;

           if (!funcType)
             werror (E_FUNC_ATTR);
           else
             {
               args=FUNC_ARGS(funcType);
               hasVargs=FUNC_HASVARARGS(funcType);

               memcpy (&funcType->funcAttrs, &$2->funcAttrs,
                   sizeof($2->funcAttrs));

               FUNC_ARGS(funcType)=args;
               FUNC_HASVARARGS(funcType)=hasVargs;

               // just to be sure
               memset (&$2->funcAttrs, 0,
                   sizeof($2->funcAttrs));

               addDecl ($1,0,$2);
             }
   }
   ;

declarator2
   : identifier
   | '(' declarator ')'     { $$ = $2; }
   | declarator3 '[' ']'
         {
            sym_link   *p;

            p = newLink (DECLARATOR);
            DCL_TYPE(p) = ARRAY ;
            DCL_ELEM(p) = 0     ;
            addDecl($1,0,p);
         }
   | declarator3 '[' constant_expr ']'
         {
            sym_link *p;
            value *tval;
            int size;

            tval = constExprValue($3, TRUE);
            /* if it is not a constant then Error  */
            p = newLink (DECLARATOR);
            DCL_TYPE(p) = ARRAY;

            if (!tval || (SPEC_SCLS(tval->etype) != S_LITERAL))
              {
                werror(E_CONST_EXPECTED);
                /* Assume a single item array to limit the cascade */
                /* of additional errors. */
                size = 1;
              }
            else
              {
                if ((size = (int) ulFromVal(tval)) < 0)
                  {
                    werror(E_NEGATIVE_ARRAY_SIZE, $1->name);
                    size = 1;
                  }
              }
            DCL_ELEM(p) = size;
            addDecl($1, 0, p);
         }
   ;

function_declarator2
   : declarator2 '('  ')'       {  addDecl ($1,FUNCTION,NULL) ;   }
   | declarator2 '('            { NestLevel++ ; currBlockno++;  }
                     parameter_type_list ')'
         {
             sym_link *funcType;

             addDecl ($1,FUNCTION,NULL) ;

             funcType = $1->type;
             while (funcType && !IS_FUNC(funcType))
               funcType = funcType->next;

             assert (funcType);

             FUNC_HASVARARGS(funcType) = IS_VARG($4);
             FUNC_ARGS(funcType) = reverseVal($4);

             /* nest level was incremented to take care of the parms  */
             NestLevel-- ;
             currBlockno--;

             // if this was a pointer (to a function)
             if (!IS_FUNC($1->type))
               cleanUpLevel(SymbolTab,NestLevel+1);

             $$ = $1;
         }
   | declarator2 '(' identifier_list ')'
         {
           werror(E_OLD_STYLE,$1->name) ;
           /* assume it returns an int */
           $1->type = $1->etype = newIntLink();
           $$ = $1 ;
         }
   ;

pointer
   : unqualified_pointer { $$ = $1 ;}
   | unqualified_pointer type_specifier_list
         {
             $$ = $1  ;
             if (IS_SPEC($2)) {
                 DCL_TSPEC($1) = $2;
                 DCL_PTR_CONST($1) = SPEC_CONST($2);
                 DCL_PTR_VOLATILE($1) = SPEC_VOLATILE($2);
                 DCL_PTR_RESTRICT($1) = SPEC_RESTRICT($2);
             }
             else
                 werror (W_PTR_TYPE_INVALID);
         }
   | unqualified_pointer pointer
         {
             $$ = $1 ;
             $$->next = $2 ;
             DCL_TYPE($2)=port->unqualified_pointer;
         }
   | unqualified_pointer type_specifier_list pointer
         {
             $$ = $1 ;
             if (IS_SPEC($2) && DCL_TYPE($3) == UPOINTER) {
                 DCL_PTR_CONST($1) = SPEC_CONST($2);
                 DCL_PTR_VOLATILE($1) = SPEC_VOLATILE($2);
                 DCL_PTR_RESTRICT($1) = SPEC_RESTRICT($2);
                 switch (SPEC_SCLS($2)) {
                 case S_XDATA:
                     DCL_TYPE($3) = FPOINTER;
                     break;
                 case S_IDATA:
                     DCL_TYPE($3) = IPOINTER ;
                     break;
                 case S_PDATA:
                     DCL_TYPE($3) = PPOINTER ;
                     break;
                 case S_DATA:
                     DCL_TYPE($3) = POINTER ;
                     break;
                 case S_CODE:
                     DCL_TYPE($3) = CPOINTER ;
                     break;
                 case S_EEPROM:
                     DCL_TYPE($3) = EEPPOINTER;
                     break;
                 default:
                   // this could be just "constant"
                   // werror(W_PTR_TYPE_INVALID);
                     ;
                 }
             }
             else
                 werror (W_PTR_TYPE_INVALID);
             $$->next = $3 ;
         }
   ;

unqualified_pointer
   :  '*'
      {
        $$ = newLink(DECLARATOR);
        DCL_TYPE($$)=UPOINTER;
      }
   ;

type_specifier_list : type_specifier_list_ { $$ = finalizeSpec($1); } ;

type_specifier_list_
   : type_specifier
   //| type_specifier_list_ type_specifier         {  $$ = mergeSpec ($1,$2, "type_specifier_list"); }
   | type_specifier_list_ type_specifier {
     /* if the decl $2 is not a specifier */
     /* find the spec and replace it      */
     $$ = mergeDeclSpec($1, $2, "type_specifier_list type_specifier skipped");
   }
   ;

identifier_list
   : identifier
   | identifier_list ',' identifier
         {
           $3->next = $1;
           $$ = $3 ;
         }
   ;

parameter_type_list
        : parameter_list
        | parameter_list ',' VAR_ARGS { $1->vArgs = 1;}
        ;

parameter_list
   : parameter_declaration
   | parameter_list ',' parameter_declaration
         {
            $3->next = $1 ;
            $$ = $3 ;
         }
   ;

parameter_declaration
   : declaration_specifiers declarator
        {
          symbol *loop;

          if (IS_SPEC ($1) && !IS_VALID_PARAMETER_STORAGE_CLASS_SPEC ($1))
            {
              werror (E_STORAGE_CLASS_FOR_PARAMETER, $2->name);
            }
          pointerTypes ($2->type, $1);
          addDecl ($2, 0, $1);
          for (loop = $2; loop; loop->_isparm = 1, loop = loop->next)
            ;
          addSymChain (&$2);
          $$ = symbolVal ($2);
          ignoreTypedefType = 0;
        }
   | type_name
        {
          $$ = newValue ();
          $$->type = $1;
          $$->etype = getSpec ($$->type);
          ignoreTypedefType = 0;
         }
   ;

type_name
   : declaration_specifiers
        {
          if (IS_SPEC ($1) && !IS_VALID_PARAMETER_STORAGE_CLASS_SPEC ($1))
            {
              werror (E_STORAGE_CLASS_FOR_PARAMETER, "type name");
            }
          $$ = $1; ignoreTypedefType = 0;
        }
   | declaration_specifiers abstract_declarator
        {
          /* go to the end of the list */
          sym_link *p;

          if (IS_SPEC ($1) && !IS_VALID_PARAMETER_STORAGE_CLASS_SPEC ($1))
            {
              werror (E_STORAGE_CLASS_FOR_PARAMETER, "type name");
            }
          pointerTypes ($2,$1);
          for (p = $2; p && p->next; p = p->next)
            ;
          if (!p)
            {
              werror(E_SYNTAX_ERROR, yytext);
            }
          else
            {
              p->next = $1 ;
            }
          $$ = $2 ;
          ignoreTypedefType = 0;
        }
   ;

abstract_declarator
   : pointer { $$ = reverseLink($1); }
   | abstract_declarator2
   | pointer abstract_declarator2   { $1 = reverseLink($1); $1->next = $2 ; $$ = $1;
          if (IS_PTR($1) && IS_FUNC($2))
            DCL_TYPE($1) = CPOINTER;
        }
   ;

abstract_declarator2
   : '(' abstract_declarator ')'    { $$ = $2 ; }
   | '[' ']'                        {
                                       $$ = newLink (DECLARATOR);
                                       DCL_TYPE($$) = ARRAY ;
                                       DCL_ELEM($$) = 0     ;
                                    }
   | '[' constant_expr ']'          {
                                       value *val ;
                                       $$ = newLink (DECLARATOR);
                                       DCL_TYPE($$) = ARRAY ;
                                       DCL_ELEM($$) = (int) ulFromVal(val = constExprValue($2,TRUE));
                                    }
   | abstract_declarator2 '[' ']'   {
                                       $$ = newLink (DECLARATOR);
                                       DCL_TYPE($$) = ARRAY ;
                                       DCL_ELEM($$) = 0     ;
                                       $$->next = $1 ;
                                    }
   | abstract_declarator2 '[' constant_expr ']'
                                    {
                                       value *val ;
                                       $$ = newLink (DECLARATOR);
                                       DCL_TYPE($$) = ARRAY ;
                                       DCL_ELEM($$) = (int) ulFromVal(val = constExprValue($3,TRUE));
                                       $$->next = $1 ;
                                    }
   | '(' ')'                        { $$ = NULL;}
   | '(' parameter_type_list ')'    { $$ = NULL;}
   | abstract_declarator2 '(' ')' {
     // $1 must be a pointer to a function
     sym_link *p=newLink(DECLARATOR);
     DCL_TYPE(p) = FUNCTION;
     if (!$1) {
       // ((void (code *) ()) 0) ()
       $1=newLink(DECLARATOR);
       DCL_TYPE($1)=CPOINTER;
       $$ = $1;
     }
     $1->next=p;
   }
   | abstract_declarator2 '(' { NestLevel++ ; currBlockno++; } parameter_type_list ')' {
       sym_link *p = newLink(DECLARATOR);
       DCL_TYPE(p) = FUNCTION;

       FUNC_HASVARARGS(p) = IS_VARG($4);
       FUNC_ARGS(p) = reverseVal($4);

       /* nest level was incremented to take care of the parms  */
       NestLevel--;
       currBlockno--;
       if (!$1) {
         /* ((void (code *) (void)) 0) () */
         $1 = newLink(DECLARATOR);
         DCL_TYPE($1) = CPOINTER;
         $$ = $1;
       }
       $1->next = p;

       // disabled to fix bug 3190029
//       // remove the symbol args (if any)
//       cleanUpLevel(SymbolTab, NestLevel+1);
   }
   ;

initializer
   : assignment_expr                { $$ = newiList(INIT_NODE,$1); }
   | '{'  initializer_list '}'      { $$ = newiList(INIT_DEEP,revinit($2)); }
   | '{'  initializer_list ',' '}'  { $$ = newiList(INIT_DEEP,revinit($2)); }
   ;

initializer_list
   : designation_opt initializer    { $2->designation = $1; $$ = $2; }
   | initializer_list ',' designation_opt initializer
                                    {
                                       $4->designation = $3;
                                       $4->next = $1;
                                       $$ = $4;
                                    }
   ;

statement
   : labeled_statement
   | compound_statement
   | expression_statement
   | selection_statement
   | iteration_statement
   | jump_statement
   | critical_statement
   | INLINEASM  ';'      {
                            ast *ex;
                            seqPointNo++;
                            ex = newNode(INLINEASM,NULL,NULL);
                            ex->values.inlineasm = strdup($1);
                            seqPointNo++;
                            $$ = ex;
                         }
   ;

critical
   : CRITICAL   {
                   inCritical++;
                   STACK_PUSH(continueStack,NULL);
                   STACK_PUSH(breakStack,NULL);
                   $$ = NULL;
                }
   ;

critical_statement
   : critical statement  {
                   STACK_POP(breakStack);
                   STACK_POP(continueStack);
                   inCritical--;
                   $$ = newNode(CRITICAL,$2,NULL);
                }
   ;

labeled_statement
//   : identifier ':' statement          {  $$ = createLabel($1,$3);  }
   : identifier ':'                    {  $$ = createLabel($1,NULL);
                                          $1->isitmp = 0;  }
   | CASE constant_expr ':'
     {
       if (STACK_EMPTY(swStk))
         $$ = createCase(NULL,$2,NULL);
       else
         $$ = createCase(STACK_PEEK(swStk),$2,NULL);
     }
   | DEFAULT { $<asts>$ = newNode(DEFAULT,NULL,NULL); } ':'
     {
       if (STACK_EMPTY(swStk))
         $$ = createDefault(NULL,$<asts>2,NULL);
       else
         $$ = createDefault(STACK_PEEK(swStk),$<asts>2,NULL);
     }
   ;

start_block : '{'
              {
                STACK_PUSH(blockNum, currBlockno);
                currBlockno = ++blockNo ;
                ignoreTypedefType = 0;
              }
            ;

end_block   : '}'     { currBlockno = STACK_POP(blockNum); }
            ;

compound_statement
   : start_block end_block                    { $$ = createBlock(NULL, NULL); }
   | start_block statement_list end_block     { $$ = createBlock(NULL, $2); }
   | start_block declaration_list end_block   { $$ = createBlock($2, NULL); }
   | start_block
          declaration_list statement_list
     end_block                                {$$ = createBlock($2, $3); }
   | error ';'                                { $$ = NULL ; }
   ;

declaration_list
   : declaration
     {
       /* if this is typedef declare it immediately */
       if ( $1 && IS_TYPEDEF($1->etype)) {
         allocVariables ($1);
         $$ = NULL ;
       }
       else
         $$ = $1 ;
       ignoreTypedefType = 0;
       addSymChain(&$1);
     }

   | declaration_list declaration
     {
       symbol   *sym;

       /* if this is a typedef */
       if ($2 && IS_TYPEDEF($2->etype)) {
         allocVariables ($2);
         $$ = $1 ;
       }
       else {
         /* get to the end of the previous decl */
         if ( $1 ) {
           $$ = sym = $1 ;
           while (sym->next)
             sym = sym->next ;
           sym->next = $2;
         }
         else
           $$ = $2 ;
       }
       ignoreTypedefType = 0;
       addSymChain(&$2);
     }
   ;

statement_list
   : statement
   | statement_list statement          {  $$ = newNode(NULLOP,$1,$2) ;}
   ;

expression_statement
   : ';'                { $$ = NULL;}
   | expr ';'           { $$ = $1; seqPointNo++;}
   ;

else_statement
   :  ELSE  statement   { $$ = $2  ; }
   |                    { $$ = NULL;}
   ;


selection_statement
   : IF '(' expr ')' { seqPointNo++;} statement else_statement
                           {
                              noLineno++ ;
                              $$ = createIf ($3, $6, $7 );
                              $$->lineno = $3->lineno;
                              $$->filename = $3->filename;
                              noLineno--;
                           }
   | SWITCH '(' expr ')'   {
                              ast *ex ;
                              static   int swLabel = 0 ;

                              seqPointNo++;
                              /* create a node for expression  */
                              ex = newNode(SWITCH,$3,NULL);
                              STACK_PUSH(swStk,ex);   /* save it in the stack */
                              ex->values.switchVals.swNum = swLabel ;

                              /* now create the label */
                              SNPRINTF(lbuff, sizeof(lbuff),
                                       "_swBrk_%d",swLabel++);
                              $<sym>$  =  newSymbol(lbuff,NestLevel);
                              /* put label in the break stack  */
                              STACK_PUSH(breakStack,$<sym>$);
                           }
     statement             {
                              /* get back the switch form the stack  */
                              $$ = STACK_POP(swStk)  ;
                              $$->right = newNode (NULLOP,$6,createLabel($<sym>5,NULL));
                              STACK_POP(breakStack);
                           }
        ;

while : WHILE  {  /* create and push the continue , break & body labels */
                  static int Lblnum = 0 ;
                  /* continue */
                  SNPRINTF (lbuff, sizeof(lbuff), "_whilecontinue_%d",Lblnum);
                  STACK_PUSH(continueStack,newSymbol(lbuff,NestLevel));
                  /* break */
                  SNPRINTF (lbuff, sizeof(lbuff), "_whilebreak_%d",Lblnum);
                  STACK_PUSH(breakStack,newSymbol(lbuff,NestLevel));
                  /* body */
                  SNPRINTF (lbuff, sizeof(lbuff), "_whilebody_%d",Lblnum++);
                  $$ = newSymbol(lbuff,NestLevel);
               }
   ;

do : DO {  /* create and push the continue , break & body Labels */
           static int Lblnum = 0 ;

           /* continue */
           SNPRINTF(lbuff, sizeof(lbuff), "_docontinue_%d",Lblnum);
           STACK_PUSH(continueStack,newSymbol(lbuff,NestLevel));
           /* break */
           SNPRINTF(lbuff, sizeof(lbuff), "_dobreak_%d",Lblnum);
           STACK_PUSH(breakStack,newSymbol(lbuff,NestLevel));
           /* do body */
           SNPRINTF(lbuff, sizeof(lbuff), "_dobody_%d",Lblnum++);
           $$ = newSymbol (lbuff,NestLevel);
        }
   ;

for : FOR { /* create & push continue, break & body labels */
            static int Lblnum = 0 ;

            /* continue */
            SNPRINTF(lbuff, sizeof(lbuff), "_forcontinue_%d",Lblnum);
            STACK_PUSH(continueStack,newSymbol(lbuff,NestLevel));
            /* break    */
            SNPRINTF(lbuff, sizeof(lbuff), "_forbreak_%d",Lblnum);
            STACK_PUSH(breakStack,newSymbol(lbuff,NestLevel));
            /* body */
            SNPRINTF(lbuff, sizeof(lbuff), "_forbody_%d",Lblnum);
            $$ = newSymbol(lbuff,NestLevel);
            /* condition */
            SNPRINTF(lbuff, sizeof(lbuff), "_forcond_%d",Lblnum++);
            STACK_PUSH(forStack,newSymbol(lbuff,NestLevel));
          }
   ;

iteration_statement
   : while '(' expr ')' { seqPointNo++;}  statement
                         {
                           noLineno++ ;
                           $$ = createWhile ( $1, STACK_POP(continueStack),
                                              STACK_POP(breakStack), $3, $6 );
                           $$->lineno = $1->lineDef;
                           $$->filename = $1->fileDef;
                           noLineno-- ;
                         }
   | do statement   WHILE '(' expr ')' ';'
                        {
                          seqPointNo++;
                          noLineno++ ;
                          $$ = createDo ( $1 , STACK_POP(continueStack),
                                          STACK_POP(breakStack), $5, $2);
                          $$->lineno = $1->lineDef;
                          $$->filename = $1->fileDef;
                          noLineno-- ;
                        }
   | for '(' expr_opt   ';' expr_opt ';' expr_opt ')'  statement
                        {
                          noLineno++ ;

                          /* if break or continue statement present
                             then create a general case loop */
                          if (STACK_PEEK(continueStack)->isref ||
                              STACK_PEEK(breakStack)->isref) {
                              $$ = createFor ($1, STACK_POP(continueStack),
                                              STACK_POP(breakStack) ,
                                              STACK_POP(forStack)   ,
                                              $3 , $5 , $7, $9 );
                          } else {
                              $$ = newNode(FOR,$9,NULL);
                              AST_FOR($$,trueLabel) = $1;
                              AST_FOR($$,continueLabel) =  STACK_POP(continueStack);
                              AST_FOR($$,falseLabel) = STACK_POP(breakStack);
                              AST_FOR($$,condLabel)  = STACK_POP(forStack)  ;
                              AST_FOR($$,initExpr)   = $3;
                              AST_FOR($$,condExpr)   = $5;
                              AST_FOR($$,loopExpr)   = $7;
                          }

                          noLineno-- ;
                        }
;

expr_opt
        :                       { $$ = NULL ; seqPointNo++; }
        |       expr            { $$ = $1 ; seqPointNo++; }
        ;

jump_statement
   : GOTO identifier ';'   {
                              $2->islbl = 1;
                              $$ = newAst_VALUE(symbolVal($2));
                              $$ = newNode(GOTO,$$,NULL);
                           }
   | CONTINUE ';'          {
       /* make sure continue is in context */
       if (STACK_EMPTY(continueStack) || STACK_PEEK(continueStack) == NULL) {
           werror(E_BREAK_CONTEXT);
           $$ = NULL;
       }
       else {
           $$ = newAst_VALUE(symbolVal(STACK_PEEK(continueStack)));
           $$ = newNode(GOTO,$$,NULL);
           /* mark the continue label as referenced */
           STACK_PEEK(continueStack)->isref = 1;
       }
   }
   | BREAK ';'             {
       if (STACK_EMPTY(breakStack) || STACK_PEEK(breakStack) == NULL) {
           werror(E_BREAK_CONTEXT);
           $$ = NULL;
       } else {
           $$ = newAst_VALUE(symbolVal(STACK_PEEK(breakStack)));
           $$ = newNode(GOTO,$$,NULL);
           STACK_PEEK(breakStack)->isref = 1;
       }
   }
   | RETURN ';'            {
       seqPointNo++;
       if (inCritical) {
           werror(E_INVALID_CRITICAL);
           $$ = NULL;
       } else {
           $$ = newNode(RETURN,NULL,NULL);
       }
   }
   | RETURN expr ';'       {
       seqPointNo++;
       if (inCritical) {
           werror(E_INVALID_CRITICAL);
           $$ = NULL;
       } else {
           $$ = newNode(RETURN,NULL,$2);
       }
   }
   ;

identifier
   : IDENTIFIER   { $$ = newSymbol ($1,NestLevel) ; }
   ;
%%
