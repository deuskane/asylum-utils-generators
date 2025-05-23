/*-------------------------------------------------------------------------
  gen.c - code generator for Z80 / Z180 / GBZ80.

  Philipp Klaus Krause pkk@spth.de, philipp@informatik.uni-frankfurt.de (2011)
  Michael Hope <michaelh@juju.net.nz> 2000
  Based on the mcs51 generator -
      Sandeep Dutta . sandeep.dutta@usa.net (1998)
   and -  Jean-Louis VERN.jlvern@writeme.com (1999)

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

/*
  Benchmarks on dhry.c 2.1 with 32766 loops and a 10ms clock:
                                       ticks dhry  size
  Base with asm strcpy / strcmp / memcpy: 23198 141 1A14
  Improved WORD push                    22784 144 19AE
  With label1 on                        22694 144 197E
  With label2 on                        22743 144 198A
  With label3 on                        22776 144 1999
  With label4 on                        22776 144 1999
  With all 'label' on                   22661 144 196F
  With loopInvariant on                 20919 156 19AB
  With loopInduction on                 Breaks    198B
  With all working on                   20796 158 196C
  Slightly better genCmp(signed)        20597 159 195B
  Better reg packing, first peephole    20038 163 1873
  With assign packing                   19281 165 1849
  5/3/00                                17741 185 17B6
  With reg params for mul and div       16234 202 162D

  1. Starting again at 3 Aug 01         34965  93 219C
   No asm strings
   Includes long mul/div in code
  2. Optimised memcpy for acc use       32102 102 226B
  3. Optimised strcpy for acc use       27819 117 2237
  3a Optimised memcpy fun
  4. Optimised strcmp fun               21999 149 2294
  5. Optimised strcmp further           21660 151 228C
  6. Optimised memcpy by unroling       20885 157 2201
  7. After turning loop induction on    19862 165 236D
  8. Same as 7 but with more info
  9. With asm optimised strings         17030 192 2223

  10 and below are with asm strings off.

  10 Mucho optimisations                13562 201 1FCC

  Apparent advantage of turning on regparams:
  1.  Cost of push
        Decent case is push of a constant
          - ld hl,#n; push hl: (10+11)*nargs
  2.  Cost of pull from stack
        Using asm with ld hl, etc
          - ld hl,#2; add hl,sp; (ld bc,(hl); hl+=2)*nargs
            10+11+(7+6+7+6)*nargs
  3.  Cost of fixing stack
          - pop hl*nargs
            10*nargs

  So cost is (10+11+7+6+7+10)*nargs+10+11
      = 51*nargs+21
      = 123 for mul, div, strcmp, strcpy
  Saving of (98298+32766+32766+32766)*123 = 24181308
  At 192 d/s for 682411768t, speed up to 199.  Hmm.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "z80.h"
#include "SDCCglobl.h"
#include "SDCCpeeph.h"
#include "gen.h"
#include "SDCCglue.h"
#include "newalloc.h"
#include "dbuf_string.h"

/* This is the down and dirty file with all kinds of kludgy & hacky
   stuff. This is what it is all about CODE GENERATION for a specific MCU.
   Some of the routines may be reusable, will have to see */

/* Z80 calling convention description.
   Parameters are passed right to left.  As the stack grows downwards,
   the parameters are arranged in left to right in memory.
   Parameters may be passed in the HL and DE registers with one
   parameter per pair.
   PENDING: What if the parameter is a long?
   Everything is caller saves. i.e. the caller must save any registers
   that it wants to preserve over the call, except for ix, which is callee saves.
   GB: The return value is returned in DEHL.  DE is normally used as a
   working register pair.  Caller saves allows it to be used for a
   return value.
   va args functions do not use register parameters.  All arguments
   are passed on the stack.
   IX is used as an index register to the top of the local variable
   area.  ix-0 is the top most local variable.
*/

enum
{
  /* Set to enable debugging trace statements in the output assembly code. */
  DISABLE_DEBUG = 0
};

//#define DEBUG_DRY_COST

static char *_z80_return[] =
  {"l", "h", "e", "d"};
static char *_gbz80_return[] =
  {"e", "d", "l", "h"};
static char *_fReceive[] =
  { "c", "b", "e", "d" };

static char **_fReturn;
static char **_fTmp;

extern struct dbuf_s *codeOutBuf;

enum
  {
    INT8MIN = -128,
    INT8MAX = 127
  };

/** Enum covering all the possible register pairs.
 */
typedef enum
  {
    PAIR_INVALID,
    PAIR_AF,
    PAIR_BC,
    PAIR_DE,
    PAIR_HL,
    PAIR_IY,
    PAIR_IX,
    NUM_PAIRS
  } PAIR_ID;

static struct
{
  const char *name;
  const char *l;
  const char *h;
} _pairs[NUM_PAIRS] = {
  {    "??1", "?2", "?3" },
  {    "af", "f", "a" },
  {    "bc", "c", "b" },
  {    "de", "e", "d" },
  {    "hl", "l", "h" },
  {    "iy", "iyl", "iyh" },
  {    "ix", "ixl", "ixh" }
};

// PENDING
#define ACC_NAME        _pairs[PAIR_AF].h

enum
  {
    LSB,
    MSB16,
    MSB24,
    MSB32
  };
    
enum asminst
  {
    A_ADD,
    A_ADC,
    A_AND,
    A_CP,
    A_CPL,
    A_DEC,
    A_INC,
    A_LD,
    A_OR,
    A_RL,
    A_RLA,
    A_RLC,
    A_RLCA,
    A_RR,
    A_RRC,
    A_RRCA,
    A_SBC,
    A_SLA,
    A_SRA,
    A_SRL,
    A_SUB,
    A_XOR
  };
  
const char *asminstnames[] =
  {
    "add",
    "adc",
    "and",
    "cp",
    "cpl",
    "dec",
    "inc",
    "ld",
    "or",
    "rl",
    "rla",
    "rlc",
    "rlca",
    "rr",
    "rrc",
    "rrca",
    "sbc",
    "sla",
    "sra",
    "srl",
    "sub",
    "xor"
  };

/** Code generator persistent data.
 */
static struct
{
  /** Used to optimised setting up of a pair by remebering what it
      contains and adjusting instead of reloading where possible.
  */
  struct
  {
    AOP_TYPE last_type;
    const char *base;
    int offset;
  } pairs[NUM_PAIRS];
  struct
  {
//    int last;
    int pushed;
    int param_offset;
    int offset;
    int pushedBC;
    int pushedDE;
    int pushedIY;
  } stack;

  struct
  {
    int pushedBC;
    int pushedDE;
  } calleeSaves;

  bool omitFramePtr;
  int frameId;
  int receiveOffset;
  bool flushStatics;
  bool in_home;
  const char *lastFunctionName;
  iCode *current_iCode;
  bool preserveCarry;

  set *sendSet;

  struct
  {
    /** TRUE if the registers have already been saved. */
    bool saved;
  } saves;

  struct
  {
    lineNode *head;
    lineNode *current;
    int isInline;
    int isDebug;
    allocTrace trace;
  } lines;

  struct
  {
    allocTrace aops;
  } trace;
} _G;

static const char *aopGet (asmop *aop, int offset, bool bit16);

struct asmop asmop_a, asmop_b, asmop_c, asmop_d, asmop_e, asmop_h, asmop_l, asmop_iyh, asmop_iyl, asmop_zero, asmop_one;
struct asmop *const ASMOP_A = &asmop_a;
struct asmop *const ASMOP_B = &asmop_b;
struct asmop *const ASMOP_C = &asmop_c;
struct asmop *const ASMOP_D = &asmop_d;
struct asmop *const ASMOP_E = &asmop_e;
struct asmop *const ASMOP_H = &asmop_h;
struct asmop *const ASMOP_L = &asmop_l;
struct asmop *const ASMOP_IYH = &asmop_iyh;
struct asmop *const ASMOP_IYL = &asmop_iyl;
struct asmop *const ASMOP_ZERO = &asmop_zero;
struct asmop *const ASMOP_ONE = &asmop_one;

static asmop *_z80_return3[] =
  {&asmop_l, &asmop_h, &asmop_e, &asmop_d};
static asmop *_gbz80_return3[] =
  {&asmop_e, &asmop_d, &asmop_l, &asmop_h};
  
static asmop *asmopregs[] = 
  {&asmop_c, &asmop_b, &asmop_e, &asmop_d, &asmop_l, &asmop_h, &asmop_iyl, &asmop_iyh};

static asmop **_fReturn3;

void
z80_init_asmops(void)
{
  asmop_a.type = AOP_ACC;
  asmop_a.size = 1;
  asmop_a.aopu.aop_str[0] = "a";
  
  asmop_b.type = AOP_REG;
  asmop_b.size = 1;
  asmop_b.aopu.aop_reg[0] = regsZ80 + B_IDX;
  asmop_c.type = AOP_REG;
  asmop_c.size = 1;
  asmop_c.aopu.aop_reg[0] = regsZ80 + C_IDX;
  asmop_d.type = AOP_REG;
  asmop_d.size = 1;
  asmop_d.aopu.aop_reg[0] = regsZ80 + D_IDX;
  asmop_e.type = AOP_REG;
  asmop_e.size = 1;
  asmop_e.aopu.aop_reg[0] = regsZ80 + E_IDX;
  asmop_h.type = AOP_REG;
  asmop_h.size = 1;
  asmop_h.aopu.aop_reg[0] = regsZ80 + H_IDX;
  asmop_l.type = AOP_REG;
  asmop_l.size = 1;
  asmop_l.aopu.aop_reg[0] = regsZ80 + L_IDX;
  asmop_iyh.type = AOP_REG;
  asmop_iyh.size = 1;
  asmop_iyh.aopu.aop_reg[0] = regsZ80 + IYH_IDX;
  asmop_iyl.type = AOP_REG;
  asmop_iyl.size = 1;
  asmop_iyl.aopu.aop_reg[0] = regsZ80 + IYL_IDX;
  
  asmop_zero.type = AOP_SIMPLELIT;
  asmop_zero.aopu.aop_simplelit = 0;
  asmop_zero.size = 1;
  
  asmop_one.type = AOP_SIMPLELIT;
  asmop_one.aopu.aop_simplelit = 1;
  asmop_one.size = 1;

  _fReturn3 = IS_GB ? _gbz80_return3 : _z80_return3;
}

extern bool regalloc_dry_run;
unsigned char regalloc_dry_run_cost; 

/* WARNING: This function is dangerous to use. It works literally:
   It will return true if ic the the last use of op, even if ic might
   be executed again, e.g. due to a loop. Most of the time you will want
   to use isPairDead(), or ic->rSurv instead of this function. */
static bool
isLastUse (const iCode *ic, operand *op)
{
  bitVect *uses = bitVectCopy (OP_USES (op));

  while (!bitVectIsZero (uses))
    {
      if (bitVectFirstBit (uses) == ic->key)
        {
          if (bitVectnBitsOn (uses) == 1)
            {
              return TRUE;
            }
          else
            {
              return FALSE;
            }
        }
      bitVectUnSetBit (uses, bitVectFirstBit (uses));
    }

  return FALSE;
}

static PAIR_ID
_getTempPairId(void)
{
  if (IS_GB)
    {
      return PAIR_DE;
    }
  else
    {
      return PAIR_HL;
    }
}

static const char *
_getTempPairName(void)
{
  return _pairs[_getTempPairId()].name;
}

static bool
isPairInUse (PAIR_ID id, const iCode *ic)
{
  if (id == PAIR_DE)
    {
      return bitVectBitValue (ic->rMask, D_IDX) || bitVectBitValue(ic->rMask, E_IDX);
    }
  else if (id == PAIR_BC)
    {
      return bitVectBitValue (ic->rMask, B_IDX) || bitVectBitValue(ic->rMask, C_IDX);
    }
  else
    {
      wassertl (0, "Only implemented for DE and BC");
      return TRUE;
    }
}

static bool
isPairDead(PAIR_ID id, const iCode *ic)
{
  const bitVect *r = (z80_opts.oldralloc ? bitVectCplAnd (bitVectCopy (ic->rMask), z80_rUmaskForOp (IC_RESULT (ic))) : ic->rSurv);

  if (id == PAIR_DE)
    {
      return !(bitVectBitValue (r, D_IDX) || bitVectBitValue(r, E_IDX));
    }
  else if (id == PAIR_BC)
    {
      return !(bitVectBitValue (r, B_IDX) || bitVectBitValue(r, C_IDX));
    }
  else if (id == PAIR_HL)
    {
      return !(bitVectBitValue (r, H_IDX) || bitVectBitValue(r, L_IDX));
    }
  else if (id == PAIR_IY)
    {
      return !(bitVectBitValue (r, IYH_IDX) || bitVectBitValue(r, IYL_IDX));
    }
  else
    {
      wassertl (0, "Only implemented for DE, BC, HL and IY");
      return TRUE;
    }
}

static PAIR_ID
getDeadPairId (const iCode *ic)
{
  if (isPairDead (PAIR_BC, ic))
    {
      return PAIR_BC;
    }
  else if (!IS_GB && isPairDead (PAIR_DE, ic))
    {
      return PAIR_DE;
    }
  else
    {
      return PAIR_INVALID;
    }
}

static PAIR_ID
getFreePairId (const iCode *ic)	// Todo: Cost
{
  if (!isPairInUse (PAIR_BC, ic))
    {
      return PAIR_BC;
    }
  else if (!IS_GB && !isPairInUse (PAIR_DE, ic))
    {
      return PAIR_DE;
    }
  else
    {
      return PAIR_INVALID;
    }
}

static void
_tidyUp (char *buf)
{
  /* Clean up the line so that it is 'prettier' */
  if (strchr (buf, ':'))
    {
      /* Is a label - cant do anything */
      return;
    }
  /* Change the first (and probably only) ' ' to a tab so
     everything lines up.
  */
  while (*buf)
    {
      if (*buf == ' ')
        {
          *buf = '\t';
          break;
        }
      buf++;
    }
}

static lineNode *
_newLineNode (const char *line)
{
  lineNode *pl;

  pl = traceAlloc(&_G.lines.trace, Safe_alloc ( sizeof (lineNode)));
  pl->line = traceAlloc(&_G.lines.trace, Safe_strdup (line));

  return pl;
}

static void
_add_line (const char *buffer)
{
  _G.lines.current = (_G.lines.current ?
              connectLine (_G.lines.current, _newLineNode (buffer)) :
              (_G.lines.head = _newLineNode (buffer)));

  _G.lines.current->isInline = _G.lines.isInline;
  _G.lines.current->isDebug = _G.lines.isDebug;
  _G.lines.current->ic = _G.current_iCode;
  _G.lines.current->isComment = (*buffer == ';');
}

static void
_vemit2 (const char *szFormat, va_list ap)
{
  struct dbuf_s dbuf;
  char *buffer, *p, *nextp;

  dbuf_init (&dbuf, INITIAL_INLINEASM);

  dbuf_tvprintf (&dbuf, szFormat, ap);

  buffer = p = dbuf_detach_c_str (&dbuf);

  _tidyUp (p);

  /* Decompose multiline macros */
  while ((nextp = strchr (p, '\n')))
    {
      *nextp = '\0';
      _add_line (p);
      p = nextp + 1;
    }

  _add_line (p);

  Safe_free (buffer);
}

static void
emitDebug (const char *szFormat,...)
{
  if(regalloc_dry_run)
    return;
  if (!options.verboseAsm)
    return;
  if (!DISABLE_DEBUG)
    {
      va_list ap;

      va_start (ap, szFormat);

      _vemit2 (szFormat, ap);

      va_end (ap);
    }
}

static PAIR_ID
getPairId (const asmop *aop)
{
  if (aop->size == 2)
    {
      if (aop->type == AOP_REG)
        {
          wassert (aop->aopu.aop_reg[0] && aop->aopu.aop_reg[1]);
          
          if ((aop->aopu.aop_reg[0]->rIdx == C_IDX) && (aop->aopu.aop_reg[1]->rIdx == B_IDX))
            {
              return PAIR_BC;
            }
          if ((aop->aopu.aop_reg[0]->rIdx == E_IDX) && (aop->aopu.aop_reg[1]->rIdx == D_IDX))
            {
              return PAIR_DE;
            }
          if ((aop->aopu.aop_reg[0]->rIdx == L_IDX) && (aop->aopu.aop_reg[1]->rIdx == H_IDX))
            {
              return PAIR_HL;
            }
        }
      else if (aop->type == AOP_STR || aop->type == AOP_HLREG)
        {
          int i;
          for (i = 0; i < NUM_PAIRS; i++)
            {
              if (!strcmp (aop->aopu.aop_str[0], _pairs[i].l) && !strcmp (aop->aopu.aop_str[1], _pairs[i].h))
                return i;
            }
        }
    }
  return PAIR_INVALID;
}

static void
emit2 (const char *szFormat,...)
{
  va_list ap;

  if(regalloc_dry_run)
    return;

  va_start (ap, szFormat);

  _vemit2 (szFormat, ap);

  va_end (ap);
}

/*-----------------------------------------------------------------*/
/* z80_emitDebuggerSymbol - associate the current code location    */
/*   with a debugger symbol                                        */
/*-----------------------------------------------------------------*/
void
z80_emitDebuggerSymbol (const char * debugSym)
{
  _G.lines.isDebug = 1;
  emit2 ("%s !equ .", debugSym);
  emit2 ("!global", debugSym);
  _G.lines.isDebug = 0;
}

// Todo: Handle IY (when used as AOP_HLREG or AOP_REG) correctly.
static unsigned char
ld_cost(asmop *op1, asmop *op2)
{
  AOP_TYPE op1type = op1->type;
  AOP_TYPE op2type = op2->type;
  
  /* Costs are symmetric */
  if(op2type == AOP_ACC || op2type == AOP_REG || op2type == AOP_HLREG || op2type == AOP_DUMMY)
    {
      asmop *tmp = op1;
      op1 = op2;
      op2 = tmp;
      op1type = op1->type;
      op2type = op2->type;
    }
  
  switch(op1type)
    {
    case AOP_ACC:
    case AOP_REG:
    case AOP_HLREG:
    case AOP_DUMMY:
      switch(op2type)
        {
        case AOP_ACC:
        case AOP_REG:
        case AOP_HLREG:
        case AOP_DUMMY:
          return(1);
        case AOP_IMMD:
        case AOP_LIT:
        case AOP_SIMPLELIT:
          return(2);
        case AOP_SFR:   /* 2 from in a, (...) */
          return((op1type == AOP_ACC || op1type == AOP_DUMMY) ? 2 : 3);
        case AOP_STK:
          return(3);
        case AOP_HL:    /* 3 from ld hl, #... */
          return(4);
        case AOP_IY:    /* 4 from ld iy, #... */
        case AOP_EXSTK: /* 4 from ld iy, #... */
          return(7);
        case AOP_PAIRPTR:
          if(op2->aopu.aop_pairId == PAIR_HL)
            return(1);
          if(op2->aopu.aop_pairId == PAIR_IY || op2->aopu.aop_pairId == PAIR_IX)
            return(3);
          if(op2->aopu.aop_pairId == PAIR_BC || op2->aopu.aop_pairId == PAIR_DE)
            return((op1type == AOP_ACC || op1type == AOP_DUMMY) ? 1 : 2);
        default:printf("ld_cost op1: AOP_REG, op2: %d", (int)(op2type));
          wassert(0);
        }
    case AOP_SFR:   /* 2 from out (...), a */
        switch(op2type)
        {
        case AOP_ACC:
        case AOP_REG:
        case AOP_HLREG:
        case AOP_DUMMY:
          return(2);
        case AOP_IMMD:
        case AOP_LIT:
        case AOP_SIMPLELIT:
          return(4);
        case AOP_STK:
          return(5);
        case AOP_HL:    /* 3 from ld hl, #... */
          return(6);
        case AOP_SFR:
          return(4);
        case AOP_IY:    /* 4 from ld iy, #... */
        case AOP_EXSTK: /* 4 from ld iy, #... */
          return(9);
        default:printf("ld_cost op1: AOP_SFR, op2: %d", (int)(op2type));
          wassert(0);
        }
    case AOP_IY:		/* 4 from ld iy, #... */
    case AOP_EXSTK:     /* 4 from ld iy, #... */
      switch(op2type)
        {
        case AOP_IMMD:
        case AOP_LIT:
        case AOP_SIMPLELIT:
          return(8);
        case AOP_SFR:   /* 2 from in a, (...) */
          return(9);
        case AOP_STK:
        case AOP_HL:    /* 3 from ld hl, #... */
          return(10);
        case AOP_IY:
        case AOP_EXSTK:
          return(16);
        default:printf("ld_cost op1: AOP_IY, op2: %d", (int)(op2type));
          wassert(0);
        }
    case AOP_STK:
      switch(op2type)
        {
        case AOP_IMMD:
        case AOP_LIT:
        case AOP_SIMPLELIT:
          return(4);
        case AOP_SFR:   /* 2 from in a, (...) */
          return(5);
        case AOP_STK:
          return(6);
        case AOP_HL:
          return(7);
        case AOP_IY:    /* 4 from ld iy, #... */
        case AOP_EXSTK:
          return(10);
        case AOP_PAIRPTR:
          if(op2->aopu.aop_pairId == PAIR_HL || op2->aopu.aop_pairId == PAIR_BC ||  op2->aopu.aop_pairId == PAIR_DE)
            return(4);
          if(op2->aopu.aop_pairId == PAIR_IY || op2->aopu.aop_pairId == PAIR_IX)
            return(6);
        default:printf("ld_cost op1: AOP_STK, op2: %d", (int)(op2type));
          wassert(0);
        }
    case AOP_HL:    /* 3 from ld hl, #... */
      switch(op2type)
        {
        case AOP_ACC:
        case AOP_REG:
        case AOP_HLREG:
        case AOP_DUMMY:
          return(4);
        case AOP_IMMD:
        case AOP_LIT:
        case AOP_SIMPLELIT:
          return(5);
        case AOP_STK:
          return(7);
        case AOP_HL:
          return(6);
        case AOP_IY:    /* 4 from ld iy, #... */
        case AOP_EXSTK:
          return(11);
        default:printf("ld_cost op1: AOP_HL, op2: %d", (int)(op2type));
          wassert(0);
        }
    case AOP_LIT:
    case AOP_SIMPLELIT:
    case AOP_IMMD:
      wassertl (0, "Trying to assign a value to a literal");
      break;
    default:
      printf("ld_cost op1: %d", (int)(op1type));
      wassert(0);
    }
  return(8); // Fallback
}

static unsigned char
op8_cost(asmop *op2)
{
  switch(op2->type)
    {
    case AOP_ACC:
    case AOP_REG:
    case AOP_HLREG:
    case AOP_DUMMY:
      return(1);
    case AOP_IMMD:
    case AOP_LIT:
    case AOP_SIMPLELIT:
      return(2);
    case AOP_STK:
      return(3);
    case AOP_HL:
      return(4);
    case AOP_IY:    /* 4 from ld iy, #... */
    case AOP_EXSTK: /* 4 from ld iy, #... */
      return(7);
    case AOP_PAIRPTR:
      if(op2->aopu.aop_pairId == PAIR_HL)
        return(1);
      if(op2->aopu.aop_pairId == PAIR_IY || op2->aopu.aop_pairId == PAIR_IX)
        return(3);     
    default:
      printf("op8_cost op2: %d", (int)(op2->type));
      wassert(0);
    }
  return(8); // Fallback
}

static unsigned char
bit8_cost(asmop *op1)
{
  switch(op1->type)
    {
    case AOP_ACC:
    case AOP_REG:
    case AOP_HLREG:
    case AOP_DUMMY:
      return(2);
    case AOP_STK:
      return(4);
    case AOP_HL:
      return(5);
    case AOP_IY:    /* 4 from ld iy, #... */
    case AOP_EXSTK: /* 4 from ld iy, #... */
      return(8);
    default:
      printf("bit8_cost op1: %d", (int)(op1->type));
      wassert(0);
    }
  return(8); //Fallback
}

static unsigned char
emit3Cost(enum asminst inst, asmop *op1, int offset1, asmop *op2, int offset2)
{
  if (op2 && offset2 >= op2->size)
    op2 = ASMOP_ZERO;

  switch(inst)
    {
    case A_CPL:
    case A_RLA:
    case A_RLCA:
    case A_RRCA:
      return(1);
    case A_LD:
      return(ld_cost(op1, op2));
      break;
    case A_ADD:
    case A_ADC:
    case A_AND:
    case A_CP:
    case A_OR:
    case A_SBC:
    case A_SUB:
    case A_XOR:
      return(op8_cost(op2));
    case A_DEC:
    case A_INC:
      return(op8_cost(op1));
    case A_RL:
    case A_RLC:
    case A_RR:
    case A_RRC:
    case A_SLA:
    case A_SRA:
    case A_SRL:
      return(bit8_cost(op1));
    default:
      wassertl(0, "Tried get cost for unknown instruction");
    }
  return(0);
}

static void
emit3_o (enum asminst inst, asmop *op1, int offset1, asmop *op2, int offset2)
{
  unsigned char cost;

  regalloc_dry_run_cost += emit3Cost(inst, op1, offset1, op2, offset2);
  if(regalloc_dry_run)
    return;

  cost = regalloc_dry_run_cost;
  if(!op1)
    emit2("%s", asminstnames[inst]);
  else if(!op2)
    emit2("%s %s", asminstnames[inst], aopGet(op1, offset1, FALSE));
  else
    {
      char *l = Safe_strdup (aopGet (op1, offset1, FALSE));
      //emit2("%s %s, %s", asminstnames[inst], aopGet(op1, offset1, FALSE), aopGet(op2, offset2, FALSE));
      emit2 ("%s %s, %s", asminstnames[inst], l, aopGet (op2, offset2, FALSE));
      Safe_free (l);
    }

  regalloc_dry_run_cost = cost;
  //emitDebug(";emit3_o cost: %d total so far: %d", (int)emit3Cost(inst, op1, offset1, op2, offset2), (int)cost);
}

static void
emit3 (enum asminst inst, asmop *op1, asmop *op2)
{
  emit3_o(inst, op1, 0, op2, 0);
}

static void
_emitMove(const char *to, const char *from)
{
  if (STRCASECMP(to, from) != 0)
    {
      emit2("ld %s,%s", to, from);
    }
  else
    {
      // Optimise it out.
      // Could leave this to the peephole, but sometimes the peephole is inhibited.
    }
}

static void
_emitMove3(asmop *to, int to_offset, asmop *from, int from_offset)
{
  /* Todo: Longer list of moves that can be optimized out. */
  if(to_offset == from_offset)
    {
      if (to->type == AOP_ACC && from->type == AOP_ACC)
        return;
      if (to->type == AOP_REG && from->type == AOP_REG && to->aopu.aop_reg[to_offset] == from->aopu.aop_reg[from_offset])
        return;
    }

  emit3_o(A_LD, to, to_offset, from, from_offset);
}

#if 0
static const char *aopNames[] = {
  "AOP_INVALID",
  "AOP_LIT",
  "AOP_REG",
  "AOP_DIR",
  "AOP_SFR",
  "AOP_STK",
  "AOP_IMMD",
  "AOP_STR",
  "AOP_CRY",
  "AOP_IY",
  "AOP_HL",
  "AOP_ACC",
  "AOP_HLREG",
  "AOP_SIMPLELIT",
  "AOP_EXSTK",
  "AOP_PAIRPT",
  "AOP_DUMMY"
};

static void
aopDump(const char *plabel, asmop *aop)
{
  int i;
  char regbuf[9];
  char *rbp = regbuf;

  emitDebug("; Dump of %s: type %s size %u", plabel, aopNames[aop->type], aop->size);
  switch (aop->type)
    {
    case AOP_EXSTK:
    case AOP_STK:
      emitDebug(";  aop_stk %d", aop->aopu.aop_stk);
      break;
    case AOP_REG:
      for (i=aop->size-1;i>=0;i--)
        *rbp++ = *(aop->aopu.aop_reg[i]->name);
      *rbp = '\0';
      emitDebug(";  reg = %s", regbuf);
      break;
    case AOP_PAIRPTR:
      emitDebug(";  pairptr = (%s)", _pairs[aop->aopu.aop_pairId].name);

    default:
      /* No information. */
      break;
    }
}
#endif

static void
_moveA(const char *moveFrom)
{
    _emitMove(ACC_NAME, moveFrom);
}

/* Load aop into A */
static void
_moveA3(asmop *from, int offset)
{
    _emitMove3(ASMOP_A, 0, from, offset);
}

static void
_clearCarry(void)
{
  emit3 (A_XOR, ASMOP_A, ASMOP_A);
}

static const char *
getPairName (asmop * aop)
{
  if (aop->type == AOP_REG)
    {
      switch (aop->aopu.aop_reg[0]->rIdx)
        {
        case C_IDX:
          return "bc";
          break;
        case E_IDX:
          return "de";
          break;
        case L_IDX:
          return "hl";
          break;
        }
    }
  else if (aop->type == AOP_STR || aop->type == AOP_HLREG)
    {
      int i;
      for (i = 0; i < NUM_PAIRS; i++)
        {
          if (strcmp(aop->aopu.aop_str[0], _pairs[i].l) == 0)
            return _pairs[i].name;
        }
    }
  wassertl (0, "Tried to get the pair name of something that isn't a pair");
  return NULL;
}

/** Returns TRUE if the registers used in aop form a pair (BC, DE, HL) */
static bool
isPair (const asmop *aop)
{
  return (getPairId (aop) != PAIR_INVALID);
}

/** Returns TRUE if the registers used in aop cannot be split into high
    and low halves */
static bool
isUnsplitable (const asmop *aop)
{
  switch (getPairId (aop))
    {
    case PAIR_IX:
    case PAIR_IY:
      return TRUE;
    default:
      return FALSE;
    }
  return FALSE;
}

static bool
isPtrPair (const asmop *aop)
{
  PAIR_ID pairId = getPairId (aop);
  switch (pairId)
    {
    case PAIR_HL:
    case PAIR_IY:
    case PAIR_IX:
      return TRUE;
    default:
      return FALSE;
    }
}

static void
spillPair (PAIR_ID pairId)
{
  _G.pairs[pairId].last_type = AOP_INVALID;
  _G.pairs[pairId].base = NULL;
}

/* Given a register name, spill the pair (if any) the register is part of */
static void
spillPairReg (const char *regname)
{
  if (strlen(regname)==1)
    {
      switch (*regname)
        {
        case 'h':
        case 'l':
          spillPair(PAIR_HL);
          break;
        case 'd':
        case 'e':
          spillPair(PAIR_DE);
          break;
        case 'b':
        case 'c':
          spillPair(PAIR_BC);
          break;
        }
    }
}

static void
_push (PAIR_ID pairId)
{
  emit2 ("push %s", _pairs[pairId].name);
  regalloc_dry_run_cost += (pairId == PAIR_IX || pairId == PAIR_IY? 2 : 1);
  _G.stack.pushed += 2;
}

static void
_pop (PAIR_ID pairId)
{
  if (pairId != PAIR_INVALID)
    {
      emit2 ("pop %s", _pairs[pairId].name);
      regalloc_dry_run_cost += (pairId == PAIR_IX || pairId == PAIR_IY? 2 : 1);
      _G.stack.pushed -= 2;
      spillPair (pairId);
    }
}

static void
genMovePairPair (PAIR_ID srcPair, PAIR_ID dstPair)
{
  switch (dstPair)
    {
    case PAIR_IX:
    case PAIR_IY:
    case PAIR_AF:
      _push(srcPair);
      _pop(dstPair);
      break;
    case PAIR_BC:
    case PAIR_DE:
    case PAIR_HL:
      if (srcPair == PAIR_IX || srcPair == PAIR_IY)
        {
          _push(srcPair);
          _pop(dstPair);
        }
      else
        {
          emit2("ld %s,%s",_pairs[dstPair].l,_pairs[srcPair].l);
          emit2("ld %s,%s",_pairs[dstPair].h,_pairs[srcPair].h);
          regalloc_dry_run_cost += 2;
        }
     default:
       wassertl (0, "Tried to move a nonphysical pair");
    }
  _G.pairs[dstPair].last_type = _G.pairs[srcPair].last_type;
  _G.pairs[dstPair].base = _G.pairs[srcPair].base;
  _G.pairs[dstPair].offset = _G.pairs[srcPair].offset;
}


/*-----------------------------------------------------------------*/
/* newAsmop - creates a new asmOp                                  */
/*-----------------------------------------------------------------*/
static asmop *
newAsmop (short type)
{
  asmop *aop;

  aop = traceAlloc(&_G.trace.aops, Safe_alloc (sizeof (asmop)));
  aop->type = type;
  return aop;
}

/*-----------------------------------------------------------------*/
/* aopForSym - for a true symbol                                   */
/*-----------------------------------------------------------------*/
static asmop *
aopForSym (const iCode * ic, symbol * sym, bool result, bool requires_a)
{
  asmop *aop;
  memmap *space;

  wassert (ic);
  wassert (sym);
  wassert (sym->etype);

  space = SPEC_OCLS (sym->etype);

  /* if already has one */
  if (sym->aop)
    {
      return sym->aop;
    }

  /* Assign depending on the storage class */
  if (sym->onStack || sym->iaccess)
    {
      /* The pointer that is used depends on how big the offset is.
         Normally everything is AOP_STK, but for offsets of < -128 or
         > 127 on the Z80 an extended stack pointer is used.
      */
      if (!IS_GB && (_G.omitFramePtr || sym->stack < INT8MIN || sym->stack > (int)(INT8MAX-getSize (sym->type))))
        {
          emitDebug ("; AOP_EXSTK for %s, _G.omitFramePtr %d, sym->stack %d, size %d", sym->rname, (int)(_G.omitFramePtr), sym->stack, getSize (sym->type));
          sym->aop = aop = newAsmop (AOP_EXSTK);
        }
      else
        {
          emitDebug ("; AOP_STK for %s", sym->rname);
          sym->aop = aop = newAsmop (AOP_STK);
        }

      aop->size = getSize (sym->type);
      aop->aopu.aop_stk = sym->stack;
      return aop;
    }

  /* special case for a function */
  if (IS_FUNC (sym->type))
    {
      sym->aop = aop = newAsmop (AOP_IMMD);
      aop->aopu.aop_immd = traceAlloc(&_G.trace.aops, Safe_strdup (sym->rname));
      aop->size = 2;
      return aop;
    }

  if( IN_REGSP( space ))
  { /*.p.t.20030716 minor restructure to add SFR support to the Z80 */
    if (IS_GB)
    {
      /* if it is in direct space */
      if( !requires_a )
      {
        sym->aop = aop = newAsmop (AOP_SFR);
        aop->aopu.aop_dir = sym->rname;
        aop->size = getSize (sym->type);
          emitDebug ("; AOP_SFR for %s", sym->rname);
        return aop;
      }
    }
    else
    { /*.p.t.20030716 adding SFR support to the Z80 port */
      aop = newAsmop (AOP_SFR);
      sym->aop          = aop;
      aop->aopu.aop_dir = sym->rname;
      aop->size         = getSize( sym->type );
      aop->paged        = FUNC_REGBANK(sym->type);
      aop->bcInUse      = isPairInUse( PAIR_BC, ic );
      emitDebug( ";Z80 AOP_SFR for %s banked:%d bc:%d", sym->rname, FUNC_REGBANK(sym->type), aop->bcInUse );

      return( aop );
    }
  }

  /* only remaining is far space */
  /* in which case DPTR gets the address */
  if (IS_GB || IY_RESERVED)
    {
      emitDebug ("; AOP_HL for %s", sym->rname);
      sym->aop = aop = newAsmop (AOP_HL);
    }
  else
      sym->aop = aop = newAsmop (AOP_IY);

  aop->size = getSize (sym->type);
  aop->aopu.aop_dir = sym->rname;

  /* if it is in code space */
  if (IN_CODESPACE (space))
    aop->code = 1;

  return aop;
}

/*-----------------------------------------------------------------*/
/* aopForRemat - rematerializes an object                          */
/*-----------------------------------------------------------------*/
static asmop *
aopForRemat (symbol * sym)
{
  iCode *ic = sym->rematiCode;
  asmop *aop = newAsmop (AOP_IMMD);
  int val = 0;
  struct dbuf_s dbuf;

  for (;;)
    {
      if (ic->op == '+')
        {
          if(isOperandLiteral (IC_RIGHT (ic)))
            {
              val += (int) operandLitValue (IC_RIGHT (ic));
              ic = OP_SYMBOL (IC_LEFT (ic))->rematiCode;
            }
          else
           {
             val += (int) operandLitValue (IC_LEFT (ic));
              ic = OP_SYMBOL (IC_RIGHT (ic))->rematiCode;
           }
        }
      else if (ic->op == '-')
        {
          val -= (int) operandLitValue (IC_RIGHT (ic));
          ic = OP_SYMBOL (IC_LEFT (ic))->rematiCode;
        }
      else if (IS_CAST_ICODE (ic))
        {
          ic = OP_SYMBOL (IC_RIGHT (ic))->rematiCode;
        }
      else
        break;
    }

  dbuf_init (&dbuf, 128);
  if (val)
    {
      dbuf_printf (&dbuf, "(%s %c 0x%04x)", OP_SYMBOL (IC_LEFT (ic))->rname, val >= 0 ? '+' : '-', abs (val) & 0xffff);
    }
  else
    {
      dbuf_append_str (&dbuf, OP_SYMBOL (IC_LEFT (ic))->rname);
    }

  aop->aopu.aop_immd = traceAlloc (&_G.trace.aops, dbuf_detach_c_str (&dbuf));
  return aop;
}

/*-----------------------------------------------------------------*/
/* regsInCommon - two operands have some registers in common       */
/*-----------------------------------------------------------------*/
static bool
regsInCommon (operand * op1, operand * op2)
{
  symbol *sym1, *sym2;
  int i;

  /* if they have registers in common */
  if (!IS_SYMOP (op1) || !IS_SYMOP (op2))
    return FALSE;

  sym1 = OP_SYMBOL (op1);
  sym2 = OP_SYMBOL (op2);

  if (sym1->nRegs == 0 || sym2->nRegs == 0)
    return FALSE;

  for (i = 0; i < sym1->nRegs; i++)
    {
      int j;
      if (!sym1->regs[i])
        continue;

      for (j = 0; j < sym2->nRegs; j++)
        {
          if (!sym2->regs[j])
            continue;

          if (sym2->regs[j] == sym1->regs[i])
            return TRUE;
        }
    }

  return FALSE;
}

/*-----------------------------------------------------------------*/
/* operandsEqu - equivalent                                        */
/*-----------------------------------------------------------------*/
static bool
operandsEqu (operand * op1, operand * op2)
{
  symbol *sym1, *sym2;

  /* if they not symbols */
  if (!IS_SYMOP (op1) || !IS_SYMOP (op2))
    return FALSE;

  sym1 = OP_SYMBOL (op1);
  sym2 = OP_SYMBOL (op2);

  /* if both are itemps & one is spilt
     and the other is not then false */
  if (IS_ITEMP (op1) && IS_ITEMP (op2) &&
      sym1->isspilt != sym2->isspilt)
    return FALSE;

  /* if they are the same */
  if (sym1 == sym2)
    return 1;

  if (sym1->rname[0] && sym2->rname[0]
      && strcmp (sym1->rname, sym2->rname) == 0)
    return 2;

  /* if left is a tmp & right is not */
  if (IS_ITEMP (op1) &&
      !IS_ITEMP (op2) &&
      sym1->isspilt &&
      (sym1->usl.spillLoc == sym2))
    return 3;

  if (IS_ITEMP (op2) &&
      !IS_ITEMP (op1) &&
      sym2->isspilt &&
      sym1->level > 0 &&
      (sym2->usl.spillLoc == sym1))
    return 4;

  return FALSE;
}

/*-----------------------------------------------------------------*/
/* sameRegs - two asmops have the same registers                   */
/*-----------------------------------------------------------------*/
static bool
sameRegs (asmop * aop1, asmop * aop2)
{
  int i;

  if (aop1->type == AOP_SFR ||
      aop2->type == AOP_SFR)
    return FALSE;

  if (aop1 == aop2)
    return TRUE;

  if (aop1->type != AOP_REG ||
      aop2->type != AOP_REG)
    return FALSE;

  if (aop1->size != aop2->size)
    return FALSE;

  for (i = 0; i < aop1->size; i++)
    if (aop1->aopu.aop_reg[i] !=
        aop2->aopu.aop_reg[i])
      return FALSE;

  return TRUE;
}

/*-----------------------------------------------------------------*/
/* aopOp - allocates an asmop for an operand  :                    */
/*-----------------------------------------------------------------*/
static void
aopOp (operand *op, const iCode *ic, bool result, bool requires_a)
{
  asmop *aop;
  symbol *sym;
  int i;

  if (!op)
    return;

  /* if this a literal */
  if (IS_OP_LITERAL (op))
    {
      op->aop = aop = newAsmop (AOP_LIT);
      aop->aopu.aop_lit = OP_VALUE (op);
      aop->size = getSize (operandType (op));
      return;
    }

  /* if already has a asmop then continue */
  if (op->aop)
    {
      if (op->aop->type == AOP_SFR)
        {
          op->aop->bcInUse = isPairInUse( PAIR_BC, ic );
        }
      return;
    }

  /* if the underlying symbol has a aop */
  if (IS_SYMOP (op) && OP_SYMBOL (op)->aop)
    {
      op->aop = OP_SYMBOL (op)->aop;
      if (op->aop->type == AOP_SFR)
        {
          op->aop->bcInUse = isPairInUse( PAIR_BC, ic );
        }
      return;
    }

  /* if this is a true symbol */
  if (IS_TRUE_SYMOP (op))
    {
      op->aop = aopForSym (ic, OP_SYMBOL (op), result, requires_a);
      return;
    }

  /* this is a temporary : this has
     only four choices :
     a) register
     b) spillocation
     c) rematerialize
     d) conditional
     e) can be a return use only */

  sym = OP_SYMBOL (op);

  /* if the type is a conditional */
  if (sym->regType == REG_CND)
    {
      aop = op->aop = sym->aop = newAsmop (AOP_CRY);
      aop->size = 0;
      return;
    }

  /* if it is spilt then two situations
     a) is rematerialize
     b) has a spill location */
  if (sym->isspilt || sym->nRegs == 0)
    {
      if (sym->ruonly)
        {
          int i;
          aop = op->aop = sym->aop = newAsmop (AOP_STR);
          aop->size = getSize (sym->type);
          for (i = 0; i < 4; i++)
            aop->aopu.aop_str[i] = _fReturn[i];
          return;
        }

      if (sym->accuse)
        {
          if (sym->accuse == ACCUSE_A)
            {
              aop = op->aop = sym->aop = newAsmop (AOP_ACC);
              aop->size = getSize (sym->type);
              wassertl(aop->size == 1, "Internal error: Caching in A, but too big to fit in A");

              aop->aopu.aop_str[0] = _pairs[PAIR_AF].h;
            }
          else if (sym->accuse == ACCUSE_SCRATCH)
            {
              aop = op->aop = sym->aop = newAsmop (AOP_HLREG);
              aop->size = getSize (sym->type);
              wassertl(aop->size <= 2, "Internal error: Caching in HL, but too big to fit in HL");
              aop->aopu.aop_str[0] = _pairs[PAIR_HL].l;
              aop->aopu.aop_str[1] = _pairs[PAIR_HL].h;
            }
          else if (sym->accuse == ACCUSE_IY)
            {
              aop = op->aop = sym->aop = newAsmop (AOP_HLREG);
              aop->size = getSize (sym->type);
              wassertl(aop->size <= 2, "Internal error: Caching in IY, but too big to fit in IY");
              aop->aopu.aop_str[0] = _pairs[PAIR_IY].l;
              aop->aopu.aop_str[1] = _pairs[PAIR_IY].h;
            }
          else
            {
              wassertl (0, "Marked as being allocated into A or HL but is actually in neither");
            }
          return;
        }
        
      /* rematerialize it NOW */
      if (sym->remat)
        {
          sym->aop = op->aop = aop =
            aopForRemat (sym);
          aop->size = getSize (sym->type);
          return;
        }

      if (regalloc_dry_run)	// Todo: Handle dummy iTemp correctly
        {
          sym->aop = op->aop = aop = newAsmop (AOP_STK);
          aop->size = getSize (sym->type);
          return;
        }
        
      if (sym->usl.spillLoc)
        {
          asmop *oldAsmOp = NULL;

          if (getSize(sym->type) != getSize(sym->usl.spillLoc->type))
            {
              /* force a new aop if sizes differ */
              oldAsmOp = sym->usl.spillLoc->aop;
              sym->usl.spillLoc->aop = NULL;
            }
          sym->aop = op->aop = aop =
                     aopForSym (ic, sym->usl.spillLoc, result, requires_a);
          if (getSize(sym->type) != getSize(sym->usl.spillLoc->type))
            {
              /* Don't reuse the new aop, go with the last one */
              sym->usl.spillLoc->aop = oldAsmOp;
            }
          aop->size = getSize (sym->type);
          return;
        }

      /* else must be a dummy iTemp */
      sym->aop = op->aop = aop = newAsmop (AOP_DUMMY);
      aop->size = getSize (sym->type);
      return;
    }

  /* must be in a register */
  sym->aop = op->aop = aop = newAsmop (AOP_REG);
  aop->size = sym->nRegs;
  for (i = 0; i < sym->nRegs; i++)
    {
      wassertl (sym->regs[i], "Symbol in register, but no register assigned.");
      aop->aopu.aop_reg[i] = sym->regs[i];
    }
}

/*-----------------------------------------------------------------*/
/* freeAsmop - free up the asmop given to an operand               */
/*----------------------------------------------------------------*/
static void
freeAsmop (operand *op, asmop *aaop, const iCode *ic)
{
  asmop *aop;

  if (!op)
    aop = aaop;
  else
    aop = op->aop;

  if (!aop)
    return;

  if (aop->freed)
    goto dealloc;

  aop->freed = 1;

  if (aop->type == AOP_PAIRPTR && !IS_GB && aop->aopu.aop_pairId == PAIR_DE)
    {
      _pop (aop->aopu.aop_pairId);
    }

  if (getPairId (aop) == PAIR_HL)
    {
      spillPair (PAIR_HL);
    }

dealloc:
  /* all other cases just dealloc */
  if (op)
    {
      op->aop = NULL;
      if (IS_SYMOP (op))
        {
          OP_SYMBOL (op)->aop = NULL;
          /* if the symbol has a spill */
          if (SPIL_LOC (op))
            SPIL_LOC (op)->aop = NULL;
        }
    }

}

static bool
isLitWord (const asmop *aop)
{
  /*    if (aop->size != 2)
     return FALSE; */
  switch (aop->type)
    {
    case AOP_IMMD:
    case AOP_LIT:
      return TRUE;
    default:
      return FALSE;
    }
}

static const char *
aopGetLitWordLong (const asmop *aop, int offset, bool with_hash)
{
  static struct dbuf_s dbuf = { 0 };

  if (dbuf_is_initialized (&dbuf))
    {
      dbuf_set_length (&dbuf, 0);
    }
  else
    {
      dbuf_init (&dbuf, 128);
    }

  /* depending on type */
  switch (aop->type)
    {
    case AOP_HL:
    case AOP_IY:
    case AOP_IMMD:
      /* PENDING: for re-target */
      if (with_hash)
        {
          dbuf_tprintf (&dbuf, "!hashedstr + %d", aop->aopu.aop_immd, offset);
        }
      else if (offset == 0)
        {
          dbuf_tprintf (&dbuf, "%s", aop->aopu.aop_immd);
        }
      else
        {
          dbuf_tprintf (&dbuf, "%s + %d", aop->aopu.aop_immd, offset);
        }
      break;

    case AOP_LIT:
      {
        value *val = aop->aopu.aop_lit;
        /* if it is a float then it gets tricky */
        /* otherwise it is fairly simple */
        if (!IS_FLOAT (val->type))
          {
            unsigned long v = ulFromVal (val);

            if (offset == 2)
              {
                v >>= 16;
              }
            else if (offset == 0)
              {
                // OK
              }
            else
              {
                wassertl(0, "Encountered an invalid offset while fetching a literal");
              }

            dbuf_tprintf (&dbuf, with_hash ? "!immedword" : "!constword", v);
          }
        else
          {
            union {
              float f;
              unsigned char c[4];
            }
            fl;
            unsigned int i;

            /* it is type float */
            fl.f = (float) floatFromVal (val);

#ifdef WORDS_BIGENDIAN
            i = fl.c[3-offset] | (fl.c[3-offset-1]<<8);
#else
            i = fl.c[offset] | (fl.c[offset+1]<<8);
#endif
            dbuf_tprintf (&dbuf, with_hash ? "!immedword" : "!constword", i);
          }
      }
      break;

    case AOP_HLREG:
    case AOP_REG:
    case AOP_STK:
    case AOP_DIR:
    case AOP_SFR:
    case AOP_STR:
    case AOP_CRY:
    case AOP_ACC:
    case AOP_SIMPLELIT:
    case AOP_EXSTK:
    case AOP_PAIRPTR:
    case AOP_DUMMY:
      break;

    default:
      dbuf_destroy (&dbuf);
      wassertl (0, "aopGetLitWordLong got unsupported aop->type");
      exit (0);
    }
  return dbuf_c_str (&dbuf);
}

static bool
isPtr (const char *s)
{
  if (!strcmp (s, "hl"))
    return TRUE;
  if (!strcmp (s, "ix"))
    return TRUE;
  if (!strcmp (s, "iy"))
    return TRUE;
  return FALSE;
}

static void
adjustPair (const char *pair, int *pold, int new_val)
{
  wassert (pair);

  while (*pold < new_val)
    {
      emit2 ("inc %s", pair);
      (*pold)++;
    }
  while (*pold > new_val)
    {
      emit2 ("dec %s", pair);
      (*pold)--;
    }
}

static void
spillCached (void)
{
  spillPair (PAIR_HL);
  spillPair (PAIR_IY);
}

static bool
requiresHL (const asmop *aop)
{
  switch (aop->type)
    {
    case AOP_IY:
    case AOP_HL:
    case AOP_STK:
    case AOP_EXSTK:
    case AOP_HLREG:

      return TRUE;
    case AOP_REG:
      {
        int i;
        for (i = 0; i < aop->size; i++)
          {
            wassert (aop->aopu.aop_reg[i]);
            if (aop->aopu.aop_reg[i]->rIdx == L_IDX || aop->aopu.aop_reg[i]->rIdx == H_IDX)
              return TRUE;
          }
      }
    default:
      return FALSE;
    }
}

static void
fetchLitPair (PAIR_ID pairId, asmop *left, int offset)
{
  const char *pair = _pairs[pairId].name;
  char *l = Safe_strdup (aopGetLitWordLong (left, offset, FALSE));
  char *base_str = Safe_strdup (aopGetLitWordLong (left, 0, FALSE));
  const char *base = base_str;

  wassert (pair);

  emitDebug(";fetchLitPair");

  if (isPtr (pair))
    {
      if (pairId == PAIR_HL || pairId == PAIR_IY)
        {
          if (pairId == PAIR_HL && base[0] == '0') // Ugly workaround
            {
               unsigned int tmpoffset;
               const char *tmpbase;
               if(sscanf(base, "%xd", &tmpoffset) && (tmpbase = strchr(base , '+')))
                 {
                   offset = tmpoffset;
                   base = tmpbase++;
                 }
            }
          if ((_G.pairs[pairId].last_type == AOP_IMMD && left->type == AOP_IMMD) ||
            (_G.pairs[pairId].last_type == AOP_IY && left->type == AOP_IY) ||
            (_G.pairs[pairId].last_type == AOP_HL && left->type == AOP_HL))
            {
              if (!regalloc_dry_run && _G.pairs[pairId].base && !strcmp (_G.pairs[pairId].base, base)) // Todo: Exact cost.
                {
                  if (pairId == PAIR_HL && abs (_G.pairs[pairId].offset - offset) < 3)
                    {
                      adjustPair (pair, &_G.pairs[pairId].offset, offset);
                      goto adjusted;
                    }
                  if (pairId == PAIR_IY && (offset >= INT8MIN && offset <= INT8MAX))
                    {
                      goto adjusted;
                    }
                }
            }
        }

      if (pairId == PAIR_HL && left->type == AOP_LIT && _G.pairs[pairId].last_type == AOP_LIT &&
        !IS_FLOAT (left->aopu.aop_lit->type) && offset == 0 && _G.pairs[pairId].offset == 0)
        {
          unsigned new_low, new_high, old_low, old_high;
          unsigned long v_new = ulFromVal (left->aopu.aop_lit);
          unsigned long v_old = strtoul (_G.pairs[pairId].base, NULL, 0);
          new_low = (v_new >> 0) & 0xff;
          new_high = (v_new >> 8) & 0xff;
          old_low = (v_old >> 0) & 0xff;
          old_high = (v_old >> 8) & 0xff;

          /* Change lower byte only. */
          if(new_high == old_high)
            {
              emit3_o (A_LD, ASMOP_L, 0, left, 0);
              goto adjusted;
            }
          /* Change upper byte only. */
          else if(new_low == old_low)
            {
              emit3_o (A_LD, ASMOP_H, 0, left, 1);
              goto adjusted;
            }
        }


      _G.pairs[pairId].last_type = left->type;
      _G.pairs[pairId].base = traceAlloc(&_G.trace.aops, Safe_strdup (base));
      _G.pairs[pairId].offset = offset;
    }
  /* Both a lit on the right and a true symbol on the left */
  emit2 ("ld %s,!hashedstr", pair, l);
  regalloc_dry_run_cost += (pairId == PAIR_IX || pairId == PAIR_IY) ? 4 : 3;
  Safe_free (base_str);
  Safe_free (l);
  return;

adjusted:
  _G.pairs[pairId].last_type = left->type;
  _G.pairs[pairId].base = traceAlloc(&_G.trace.aops, Safe_strdup (base));
  _G.pairs[pairId].offset = offset;
  Safe_free (base_str);
  Safe_free (l);
}

static PAIR_ID
makeFreePairId (const iCode *ic, bool *pisUsed)
{
  *pisUsed = FALSE;

  if (ic != NULL)
    {
      if (!bitVectBitValue (ic->rMask, B_IDX) && !bitVectBitValue(ic->rMask, C_IDX))
        {
          return PAIR_BC;
        }
      else if (!IS_GB && !bitVectBitValue (ic->rMask, D_IDX) && !bitVectBitValue(ic->rMask, E_IDX))
        {
          return PAIR_DE;
        }
      else
        {
          *pisUsed = TRUE;
          return PAIR_HL;
        }
    }
  else
    {
      *pisUsed = TRUE;
      return PAIR_HL;
    }
}

static void
fetchPairLong (PAIR_ID pairId, asmop *aop, const iCode *ic, int offset)
{
    emitDebug(";fetchPairLong");

    /* if this is rematerializable */
    if (isLitWord (aop))
      fetchLitPair (pairId, aop, offset);
    else
      {
        if (getPairId (aop) == pairId)
          {
            /* Do nothing */
          }
        /* we need to get it byte by byte */
        else if (pairId == PAIR_HL && (IS_GB || (IY_RESERVED && aop->type == AOP_HL)) && requiresHL (aop))
          {
            if (!regalloc_dry_run) // TODO: Fix this to get correct cost!
              aopGet (aop, offset, FALSE);
            switch (aop->size - offset) {
            case 1:
              emit2 ("ld l,!*hl");
              emit2 ("ld h,!immedbyte", 0);
              regalloc_dry_run_cost += 3;
              break;
            case 2:
              // PENDING: Requires that you are only fetching two bytes.
            case 4:
              if (IS_R2K)
                {
                  emit2 ("ld hl, (hl)");
                  regalloc_dry_run_cost += 3;
                }
              else
                {
                  emit2 ("ld a,!*hl");
                  emit2 ("inc hl");
                  emit2 ("ld h,!*hl");
                  emit2 ("ld l,a");
                  regalloc_dry_run_cost += 4;
                }
              break;
            default:
              wassertl (0, "Attempted to fetch too much data into HL");
              break;
            }
          }
        else if (!IS_GB && aop->type == AOP_IY && !(pairId == PAIR_IY && aop->size < 2)) {
          /* Instead of fetching relative to IY, just grab directly
             from the address IY refers to */
          emit2 ("ld %s,(%s)", _pairs[pairId].name, aopGetLitWordLong (aop, offset, FALSE));
          regalloc_dry_run_cost += (pairId == PAIR_IY ? 4 : 3);

          if (aop->size < 2) {
            emit2("ld %s,!zero", _pairs[pairId].h);
            regalloc_dry_run_cost += 2;
          }
        }
        else if (pairId == PAIR_IY)
          {
#ifdef ALL_RABBIT
            if (isPair (aop) && IS_R2K && getPairId (aop) == PAIR_HL)
              {
                emit2 ("ld iy, hl");
                regalloc_dry_run_cost += 2;
              }
#endif
            if (isPair (aop))
              {
                emit2 ("push %s", _pairs[getPairId(aop)].name);
                emit2 ("pop iy");
                regalloc_dry_run_cost += 3;
              }
            else
              {
                bool isUsed;
                PAIR_ID id = makeFreePairId (ic, &isUsed);
                if (isUsed)
                  _push (id);
                /* Can't load into parts, so load into HL then exchange. */
                if (!regalloc_dry_run)
                  {
                    emit2 ("ld %s,%s", _pairs[id].l, aopGet (aop, offset, FALSE));
                    emit2 ("ld %s,%s", _pairs[id].h, aopGet (aop, offset + 1, FALSE));
                    
                  }
                regalloc_dry_run_cost += ld_cost(ASMOP_L, aop) + ld_cost(ASMOP_H, aop);
#ifdef ALL_RABBIT
                if (IS_R2K && id == PAIR_HL) ld iy, hl is not yet supported by the assembler
                  {
                    emit2 ("ld iy, hl");
                    regalloc_dry_run_cost += 2;
                  }
                else
#endif
                  {
                    emit2 ("push %s", _pairs[id].name);
                    emit2 ("pop iy");
                    regalloc_dry_run_cost += 3;
                  }
                if (isUsed)
                  _pop (id);
              }
          }
        else if (isUnsplitable(aop))
          {
            emit2("push %s", _pairs[getPairId(aop)].name);
            emit2("pop %s", _pairs[pairId].name);
            regalloc_dry_run_cost += (pairId == PAIR_IY ? 2 : 1) + (getPairId(aop) == PAIR_IY ? 2 : 1);
          }
        else
          {
            /* The Rabbit has the ld hl, n (sp) and ld hl, n (ix) instructions. */
            int fp_offset = aop->aopu.aop_stk + offset + _G.stack.offset + (aop->aopu.aop_stk > 0 ? _G.stack.param_offset : 0);
            int sp_offset = fp_offset + _G.stack.pushed;
            if (IS_GB && aop->size - offset >= 2 && aop->type == AOP_STK && pairId == PAIR_HL && abs (sp_offset) <= 127)
              {
                emit2 ("ld hl, %d (sp)", sp_offset); /* Fetch relative to stack pointer. */
              }
            else if (IS_R2K && aop->size - offset >= 2 && aop->type == AOP_STK && (pairId == PAIR_HL || pairId == PAIR_IY) &&
              (abs (fp_offset) <= 127 && pairId == PAIR_HL || abs (sp_offset) <= 127))
              {
                if (abs (sp_offset) <= 127)
                  emit2 ("ld %s, %d (sp)", pairId == PAIR_IY ? "iy" : "hl", sp_offset); /* Fetch relative to stack pointer. */
                else
                  emit2 ("ld hl, %d (ix)", fp_offset); /* Fetch relative to frame pointer. */
                regalloc_dry_run_cost += (pairId == PAIR_HL ? 2 : 3);
              }

            /* Operand resides (partially) in the pair */
            else if (!regalloc_dry_run && !strcmp(aopGet (aop, offset + 1, FALSE), _pairs[pairId].l))	// Todo: Exact cost
              {
                _moveA3 (aop, offset + 1);
                if(!regalloc_dry_run)
                  emit2 ("ld %s,%s", _pairs[pairId].l, aopGet (aop, offset, FALSE));
                regalloc_dry_run_cost += ld_cost(ASMOP_A, aop);
                emit2 ("ld %s,a", _pairs[pairId].h);
                regalloc_dry_run_cost += 1;
              }
            else
              {
                if(!regalloc_dry_run)
                  {
                    emit2 ("ld %s,%s", _pairs[pairId].l, aopGet (aop, offset, FALSE));
                    emit2 ("ld %s,%s", _pairs[pairId].h, aopGet (aop, offset + 1, FALSE));
                  }
                regalloc_dry_run_cost += ld_cost(ASMOP_L, aop) * 2;           
              }
          }
        /* PENDING: check? */
        spillPair (pairId);
    }
}

static void
fetchPair (PAIR_ID pairId, asmop * aop)
{
  fetchPairLong (pairId, aop, NULL, 0);
}

static void
fetchHL (asmop * aop)
{
  fetchPair (PAIR_HL, aop);
}

static void
setupPairFromSP (PAIR_ID id, int offset)
{
  wassertl (id == PAIR_HL, "Setup relative to SP only implemented for HL");

  if (_G.preserveCarry)
    {
      _push (PAIR_AF);
      offset += 2;
    }

  if (offset < INT8MIN || offset > INT8MAX)
    {
      emit2 ("ld hl,!immedword", offset);
      emit2 ("add hl,sp");
      regalloc_dry_run_cost += 4;
    }
  else
    {
      emit2 ("!ldahlsp", offset);
      regalloc_dry_run_cost += 4;	// Todo: More exact cost.
    }

  if (_G.preserveCarry)
    {
      _pop (PAIR_AF);
      offset -= 2;
    }
}

static void
setupPair (PAIR_ID pairId, asmop *aop, int offset)
{
  switch (aop->type)
    {
    case AOP_IY:
      wassertl (pairId == PAIR_IY || pairId == PAIR_HL, "AOP_IY must be in IY or HL");
      fetchLitPair (pairId, aop, 0);
      break;

    case AOP_HL:
      wassertl (pairId == PAIR_HL, "AOP_HL must be in HL");

      fetchLitPair (pairId, aop, offset);
      _G.pairs[pairId].offset = offset;
      break;

    case AOP_EXSTK:
      wassertl (!IS_GB, "The GBZ80 doesn't have an extended stack");
      wassertl (pairId == PAIR_IY || pairId == PAIR_HL, "The Z80 extended stack must be in IY or HL");

      {
        int offset = aop->aopu.aop_stk + _G.stack.offset;

        if (aop->aopu.aop_stk >= 0)
          offset += _G.stack.param_offset;

        if (_G.pairs[pairId].last_type == aop->type && _G.pairs[pairId].offset == offset)
          {
            /* Already setup */
          }
        else
          {
            struct dbuf_s dbuf;

            /* PENDING: Do this better. */
            if (_G.preserveCarry)
              _push (PAIR_AF);
            dbuf_init (&dbuf, 128);
            dbuf_printf (&dbuf, "%d", offset + _G.stack.pushed);
            emit2 ("ld %s,!hashedstr", _pairs[pairId].name, dbuf_c_str (&dbuf));
            dbuf_destroy (&dbuf);
            emit2 ("add %s,sp", _pairs[pairId].name);
            _G.pairs[pairId].last_type = aop->type;
            _G.pairs[pairId].offset = offset;
            if (_G.preserveCarry)
              _pop (PAIR_AF);
          }
      }
      break;

    case AOP_STK:
      {
        /* Doesnt include _G.stack.pushed */
        int abso = aop->aopu.aop_stk + offset + _G.stack.offset + (aop->aopu.aop_stk > 0 ? _G.stack.param_offset : 0);

        assert (pairId == PAIR_HL);
        /* In some cases we can still inc or dec hl */
        if (_G.pairs[pairId].last_type == AOP_STK && abs (_G.pairs[pairId].offset - abso) < 3)
          {
            adjustPair (_pairs[pairId].name, &_G.pairs[pairId].offset, abso);
          }
        else
          {
            setupPairFromSP (PAIR_HL, abso + _G.stack.pushed);
          }
        _G.pairs[pairId].offset = abso;
        break;
      }

    case AOP_PAIRPTR:
      if (pairId != aop->aopu.aop_pairId)
        genMovePairPair(aop->aopu.aop_pairId, pairId);
      adjustPair (_pairs[pairId].name, &_G.pairs[pairId].offset, offset);
      break;

    default:
      wassert (0);
    }
  _G.pairs[pairId].last_type = aop->type;
}

/* Can be used for local labels where Code generation takes care of spilling */
static void
emitLabelNoSpill (int key)
{
  emit2 ("!tlabeldef", key);
  _G.lines.current->isLabel = 1;
}

static void
emitLabel (int key)
{
  emit2 ("!tlabeldef", key);
  _G.lines.current->isLabel = 1;
  spillCached ();
}

/*-----------------------------------------------------------------*/
/* aopGet - for fetching value of the aop                          */
/*-----------------------------------------------------------------*/
static const char *
aopGet (asmop * aop, int offset, bool bit16)
{
  static struct dbuf_s dbuf = { 0 };

  wassert (!regalloc_dry_run);

  if (dbuf_is_initialized (&dbuf))
    {
      /* reuse the dynamically allocated buffer */
      dbuf_set_length (&dbuf, 0);
    }
  else
    {
      /* first time: initialize the dynamically allocated buffer */
      dbuf_init (&dbuf, 128);
    }

  /* offset is greater than size then zero */
  /* PENDING: this seems a bit screwed in some pointer cases. */
  if (offset > (aop->size - 1) && aop->type != AOP_LIT)
    {
      dbuf_tprintf (&dbuf, "!zero");
    }
  else
    {
      /* depending on type */
      switch (aop->type)
        {
        case AOP_DUMMY:
          dbuf_append_char (&dbuf, 'a');
          break;

        case AOP_IMMD:
          /* PENDING: re-target */
          if (bit16)
            dbuf_tprintf (&dbuf, "!immedwords", aop->aopu.aop_immd);
          else
            {
              switch (offset)
                {
                case 2:
                  dbuf_tprintf (&dbuf, "!bankimmeds", aop->aopu.aop_immd);
                  break;

                case 1:
                  dbuf_tprintf (&dbuf, "!msbimmeds", aop->aopu.aop_immd);
                  break;

                case 0:
                  dbuf_tprintf (&dbuf, "!lsbimmeds", aop->aopu.aop_immd);
                  break;

                default:
                  wassertl (0, "Fetching from beyond the limits of an immediate value.");
                }
            }
          break;

        case AOP_DIR:
          wassert (IS_GB);
          emit2 ("ld a,(%s+%d)", aop->aopu.aop_dir, offset);
          dbuf_append_char (&dbuf, 'a');
          break;

        case AOP_SFR:
          if (IS_GB)
            {
              emit2 ("ldh a,(%s+%d)", aop->aopu.aop_dir, offset);
              dbuf_append_char (&dbuf, 'a');
            }
          else if (IS_R2K)
            {
              emit2 ("ioi");
              emit2 ("ld a,(%s)", aop->aopu.aop_dir);
              emit2 ("nop");	/* Workaround for Rabbit 2000 hardware bug. see TN302 for details. */
              dbuf_append_char (&dbuf, 'a');
            }
          else
            {                   /*.p.t.20030716 handling for i/o port read access for Z80 */
              if (aop->paged)
                {               /* banked mode */
                  /* reg A goes to address bits 15-8 during "in a,(x)" instruction */
                  emit2 ("ld a,!msbimmeds", aop->aopu.aop_dir);
                  emit2 ("in a,(!lsbimmeds)", aop->aopu.aop_dir);
                }
              else if (z80_opts.port_mode == 180)
                {               /* z180 in0/out0 mode */
                  emit2 ("in0 a,(%s)", aop->aopu.aop_dir);
                }
              else
                {               /* 8 bit mode */
                  emit2 ("in a,(%s)", aop->aopu.aop_dir);
                }

              dbuf_append_char (&dbuf, 'a');
            }
          break;

        case AOP_REG:
          dbuf_append_str (&dbuf, aop->aopu.aop_reg[offset]->name);
          break;

        case AOP_HL:
          setupPair (PAIR_HL, aop, offset);
          dbuf_tprintf (&dbuf, "!*hl");
          break;

        case AOP_IY:
          wassert (!IS_GB);
          setupPair (PAIR_IY, aop, offset);
          dbuf_tprintf (&dbuf, "!*iyx", offset);
          break;

        case AOP_EXSTK:
          wassert (!IS_GB);
          setupPair (PAIR_IY, aop, offset);
          dbuf_tprintf (&dbuf, "!*iyx", offset);
          break;

        case AOP_STK:
          if (IS_GB)
            {
              setupPair (PAIR_HL, aop, offset);
              dbuf_tprintf (&dbuf, "!*hl");
            }
          else if (_G.omitFramePtr)
            {
              if (aop->aopu.aop_stk >= 0)
                offset += _G.stack.param_offset;
              setupPair (PAIR_IX, aop, offset);
              dbuf_tprintf (&dbuf, "!*ixx", offset);
            }
          else
            {
              if (aop->aopu.aop_stk >= 0)
                offset += _G.stack.param_offset;
              dbuf_tprintf (&dbuf, "!*ixx", aop->aopu.aop_stk + offset);
            }
          break;

        case AOP_CRY:
          wassertl (0, "Tried to fetch from a bit variable");
          break;

        case AOP_ACC:
          if (!offset)
            {
              dbuf_append_char (&dbuf, 'a');
            }
          else
            {
              dbuf_tprintf (&dbuf, "!zero");
            }
          break;

        case AOP_HLREG:
          dbuf_append_str (&dbuf, aop->aopu.aop_str[offset]);
          break;

        case AOP_LIT:
          dbuf_append_str (&dbuf, aopLiteral (aop->aopu.aop_lit, offset));
          break;

        case AOP_SIMPLELIT:
          {
            unsigned long v = aop->aopu.aop_simplelit;

            v >>= (offset * 8);
            dbuf_tprintf (&dbuf, "!immedbyte", (unsigned int) v & 0xff);
          }
          break;

        case AOP_STR:
          aop->coff = offset;
          dbuf_append_str (&dbuf, aop->aopu.aop_str[offset]);
          break;

        case AOP_PAIRPTR:
          setupPair (aop->aopu.aop_pairId, aop, offset);
          if (aop->aopu.aop_pairId == PAIR_IX)
            dbuf_tprintf (&dbuf, "!*ixx", offset);
          else if (aop->aopu.aop_pairId == PAIR_IY)
            dbuf_tprintf (&dbuf, "!*iyx", offset);
          else
            dbuf_printf (&dbuf, "(%s)", _pairs[aop->aopu.aop_pairId].name);
          break;

        default:
          dbuf_destroy (&dbuf);
          wassertl (0, "aopget got unsupported aop->type");
          exit (0);
        }
    }
  return dbuf_c_str (&dbuf);
}

static bool
isRegString (const char *s)
{
  if (!strcmp (s, "b") ||
      !strcmp (s, "c") ||
      !strcmp (s, "d") ||
      !strcmp (s, "e") ||
      !strcmp (s, "a") ||
      !strcmp (s, "h") ||
      !strcmp (s, "l"))
    return TRUE;
  return FALSE;
}

static bool
isConstantString (const char *s)
{
  /* This is a bit of a hack... */
  return (*s == '#' || *s == '$');
}

static bool
canAssignToPtr (const char *s)
{
  if (isRegString (s))
    return TRUE;
  if (isConstantString (s))
    return TRUE;
  return FALSE;
}

static bool
canAssignToPtr3 (const asmop *aop)
{
  if(aop->type == AOP_ACC || aop->type == AOP_REG || aop->type == AOP_HLREG)
    return(TRUE);
  if(aop->type == AOP_IMMD || aop->type == AOP_LIT || aop->type == AOP_SIMPLELIT)
    return(TRUE);
  return(FALSE);
}

/*-----------------------------------------------------------------*/
/* aopPut - puts a string for a aop                                */
/*-----------------------------------------------------------------*/
static void
aopPut (asmop *aop, const char *s, int offset)
{
  struct dbuf_s dbuf;

  wassert (!regalloc_dry_run);

  if (aop->size && offset > (aop->size - 1))
    {
      werror (E_INTERNAL_ERROR, __FILE__, __LINE__,
              "aopPut got offset > aop->size");
      exit (0);
    }

  // PENDING
  dbuf_init (&dbuf, 128);
  dbuf_tprintf (&dbuf, s);
  s = dbuf_c_str (&dbuf);

  /* will assign value to value */
  /* depending on where it is of course */
  switch (aop->type)
    {
    case AOP_DUMMY:
      _moveA (s);  /* in case s is volatile */
      break;

    case AOP_DIR:
      /* Direct.  Hmmm. */
      wassert (IS_GB);
      if (strcmp (s, "a"))
        emit2 ("ld a,%s", s);
      emit2 ("ld (%s+%d),a", aop->aopu.aop_dir, offset);
      break;

    case AOP_SFR:
      if (IS_GB)
        {
          //  wassert (IS_GB);
          if (strcmp (s, "a"))
            emit2 ("ld a,%s", s);
          emit2 ("ldh (%s+%d),a", aop->aopu.aop_dir, offset);
        }
      else if (IS_R2K)
        {
          if (strcmp (s, "a"))
            emit2 ("ld a,%s", s);
	  
          /* LM 20110928: Need to fix to emit either "ioi" or "ioe"
           * (for internal vs. external I/O space
           */
          emit2 ("ioi");
          emit2 ("ld (%s),a", aop->aopu.aop_dir);
          emit2 ("nop"); /* Workaround for Rabbit 2000 hardware bug. see TN302 for details. */
        }
      else
        { /*.p.t.20030716 handling for i/o port read access for Z80 */
          if (aop->paged)
            { /* banked mode */
              if (aop->bcInUse)
                emit2( "push bc" );

              if (strlen(s) != 1
                  || (s[0] != 'a' && s[0] != 'd' && s[0] != 'e'
                      && s[0] != 'h' && s[0] != 'l'))
                {
                  emit2( "ld a,%s", s );
                  s = "a";
                }

              emit2( "ld bc,#%s", aop->aopu.aop_dir );
              emit2( "out (c),%s", s );

              if( aop->bcInUse )
                emit2( "pop bc"    );
              else
                spillPair (PAIR_BC);
            }
          else if( z80_opts.port_mode == 180 )
            { /* z180 in0/out0 mode */
              emit2( "ld a,%s", s );
              emit2( "out0 (%s),a", aop->aopu.aop_dir );
            }
          else
            { /* 8 bit mode */
              emit2( "ld a,%s", s );
              emit2( "out (%s),a", aop->aopu.aop_dir );
            }
        }
      break;

    case AOP_REG:
      if (!strcmp (s, "!*hl"))
        emit2 ("ld %s,!*hl", aop->aopu.aop_reg[offset]->name);
      else
        emit2 ("ld %s,%s",
               aop->aopu.aop_reg[offset]->name, s);
      spillPairReg(aop->aopu.aop_reg[offset]->name);
      break;

    case AOP_IY:
      wassert (!IS_GB);
      if (!canAssignToPtr (s))
        {
          emit2 ("ld a,%s", s);
          setupPair (PAIR_IY, aop, offset);
          emit2 ("ld !*iyx,a", offset);
        }
      else
        {
          setupPair (PAIR_IY, aop, offset);
          emit2 ("ld !*iyx,%s", offset, s);
        }
      break;

    case AOP_HL:
      //wassert (IS_GB);
      /* PENDING: for re-target */
      if (!strcmp (s, "!*hl") || !strcmp (s, "(hl)") || !strcmp (s, "[hl]"))
        {
          emit2 ("ld a,!*hl");
          s = "a";
        }
      setupPair (PAIR_HL, aop, offset);

      emit2 ("ld !*hl,%s", s);
      break;

    case AOP_EXSTK:
      wassert (!IS_GB);
      if (!canAssignToPtr (s))
        {
          emit2 ("ld a,%s", s);
          setupPair (PAIR_IY, aop, offset);
          emit2 ("ld !*iyx,a", offset);
        }
      else
        {
          setupPair (PAIR_IY, aop, offset);
          emit2 ("ld !*iyx,%s", offset, s);
        }
      break;

    case AOP_STK:
      if (IS_GB)
        {
          /* PENDING: re-target */
          if (!strcmp (s, "!*hl") || !strcmp (s, "(hl)") || !strcmp (s, "[hl]"))
            {
              emit2 ("ld a,!*hl");
              s = "a";
            }
          setupPair (PAIR_HL, aop, offset);
          if (!canAssignToPtr (s))
            {
              emit2 ("ld a,%s", s);
              emit2 ("ld !*hl,a");
            }
          else
            emit2 ("ld !*hl,%s", s);
        }
      else
        {
          if (aop->aopu.aop_stk >= 0)
            offset += _G.stack.param_offset;
          if (!canAssignToPtr (s))
            {
              emit2 ("ld a,%s", s);
              emit2 ("ld !*ixx,a", aop->aopu.aop_stk + offset);
            }
          else
            {
              emit2 ("ld !*ixx,%s", aop->aopu.aop_stk + offset, s);
            }
        }
      break;

    case AOP_CRY:
      /* if bit variable */
      if (!aop->aopu.aop_dir)
        {
          emit2 ("ld a,!zero");
          emit2 ("rla");
        }
      else
        {
          /* In bit space but not in C - cant happen */
          wassertl (0, "Tried to write into a bit variable");
        }
      break;

    case AOP_STR:
      aop->coff = offset;
      if (strcmp (aop->aopu.aop_str[offset], s))
        {
          emit2 ("ld %s,%s", aop->aopu.aop_str[offset], s);
        }
      spillPairReg(aop->aopu.aop_str[offset]);
      break;

    case AOP_ACC:
      aop->coff = offset;
      if (!offset && (strcmp (s, "acc") == 0))
        break;
      if (offset > 0)
        {
          wassertl (0, "Tried to access past the end of A");
        }
      else
        {
          wassert (aop->aopu.aop_str[offset]);
          wassert (s);
          if (strcmp (aop->aopu.aop_str[offset], s))
            {
              emit2 ("ld %s,%s", aop->aopu.aop_str[offset], s);
              spillPairReg(aop->aopu.aop_str[offset]);
            }
        }
      break;

    case AOP_HLREG:
      wassert (offset < 2);
      emit2 ("ld %s,%s", aop->aopu.aop_str[offset], s);
      spillPairReg(aop->aopu.aop_str[offset]);
      break;

    case AOP_PAIRPTR:
      setupPair (aop->aopu.aop_pairId, aop, offset);
      if (aop->aopu.aop_pairId==PAIR_IX)
        emit2 ("ld !*ixx,%s", 0, s);
      else if (aop->aopu.aop_pairId==PAIR_IY)
        emit2 ("ld !*iyx,%s", 0, s);
      else
        emit2 ("ld (%s),%s", _pairs[aop->aopu.aop_pairId].name, s);
      break;

    default:
      dbuf_destroy (&dbuf);
      werror (E_INTERNAL_ERROR, __FILE__, __LINE__, "aopPut got unsupported aop->type");
      exit (0);
    }
  dbuf_destroy (&dbuf);
}

static void
aopPut3 (asmop *op1, int offset1, asmop *op2, int offset2)
{
  unsigned char cost = regalloc_dry_run_cost;

  if(!regalloc_dry_run)
    aopPut (op1, aopGet(op2, offset2, FALSE), offset1);
  regalloc_dry_run_cost = cost + ld_cost(op1, offset2 < op2->size ? op2 : ASMOP_ZERO);
}

// Move, but try not to.
static void
cheapMove (asmop *to, int to_offset, asmop *from, int from_offset)
{
  /* Todo: Longer list of moves that can be optimized out. */
  if (to->type == AOP_ACC && from->type == AOP_ACC && to_offset == from_offset)
    return;
  if (to->type == AOP_REG && from->type == AOP_REG && to->aopu.aop_reg[to_offset] == from->aopu.aop_reg[from_offset])
    return;
  if (to->type == AOP_HLREG && from->type == AOP_HLREG && !strcmp(to->aopu.aop_str[to_offset], from->aopu.aop_str[from_offset]))
    return;
  aopPut3 (to, to_offset, from, from_offset);
}

#define AOP(op) op->aop
#define AOP_TYPE(op) AOP(op)->type
#define AOP_SIZE(op) AOP(op)->size
#define AOP_NEEDSACC(x) (AOP(x) && ((AOP_TYPE(x) == AOP_CRY) || (AOP_TYPE(x) == AOP_SFR)))
#define AOP_IS_PAIRPTR(x, p) (AOP_TYPE (x) == AOP_PAIRPTR && AOP (x)->aopu.aop_pairId == p)

static void
commitPair (asmop * aop, PAIR_ID id)
{
  int fp_offset = aop->aopu.aop_stk + _G.stack.offset + (aop->aopu.aop_stk > 0 ? _G.stack.param_offset : 0);
  int sp_offset = fp_offset + _G.stack.pushed;
  if (IS_R2K && aop->type == AOP_STK && (id == PAIR_HL || id == PAIR_IY) &&
    (id == PAIR_HL && abs (fp_offset) <= 127 || abs (sp_offset) <= 127))
    {
      if (abs (sp_offset) <= 127)
        emit2 ("ld %d (sp), %s", sp_offset, id == PAIR_IY ? "iy" : "hl"); /* Relative to stack pointer. */
      else
        emit2 ("ld %d (ix), hl", fp_offset); /* Relative to frame pointer. */
      regalloc_dry_run_cost += (id == PAIR_HL ? 2 : 3);
    }

  /* PENDING: Verify this. */
  else if (id == PAIR_HL && requiresHL (aop) && (IS_GB || IY_RESERVED))
    {
      if(!regalloc_dry_run)
        {
          emit2 ("ld a,l");
          emit2 ("ld d,h");
          aopPut (aop, "a", 0);
          aopPut (aop, "d", 1);
        }
      regalloc_dry_run_cost += (2 + ld_cost(aop, ASMOP_A) + ld_cost(aop, ASMOP_D));
    }
  else
    {
      /* Special cases */
      if (id == PAIR_HL && aop->type == AOP_IY && aop->size == 2)
        {
          if(!regalloc_dry_run)
            {
              emit2 ("ld (%s),%s", aopGetLitWordLong (aop, 0, FALSE), _pairs[id].name);
            }
          regalloc_dry_run_cost += 3;
        }
      else
        {
          switch (id)
            {
            case PAIR_BC:
              cheapMove (aop, 0, ASMOP_C, 0);
              cheapMove (aop, 1, ASMOP_B, 0);
              break;
            case PAIR_DE:
              cheapMove (aop, 0, ASMOP_E, 0);
              cheapMove (aop, 1, ASMOP_D, 0);
              break;
            case PAIR_HL:
              if (aop->type == AOP_REG && aop->aopu.aop_reg[0]->rIdx == H_IDX && aop->aopu.aop_reg[1]->rIdx ==  L_IDX)
                {
                  cheapMove (ASMOP_A, 0, ASMOP_L, 0);
                  cheapMove (aop, 1, ASMOP_H, 0);
                  cheapMove (aop, 0, ASMOP_A, 0);
                }
              else if (aop->type == AOP_REG && aop->aopu.aop_reg[0]->rIdx ==  H_IDX) // Do not overwrite upper byte.
                {
                  cheapMove (aop, 1, ASMOP_H, 0);
                  cheapMove (aop, 0, ASMOP_L, 0);
                }
              else
                {
                  cheapMove (aop, 0, ASMOP_L, 0);
                  cheapMove (aop, 1, ASMOP_H, 0);
                }
              break;
            default:
              wassertl (0, "Unknown pair id in commitPair()");
            }
        }
    }
}

/*-----------------------------------------------------------------*/
/* getDataSize - get the operand data size                         */
/*-----------------------------------------------------------------*/
static int
getDataSize (operand * op)
{
  int size;
  size = AOP_SIZE (op);
  if (size == 3)
    {
      /* pointer */
      wassertl (0, "Somehow got a three byte data pointer");
    }
  return size;
}

/*-----------------------------------------------------------------*/
/* movLeft2Result - move byte from left to result                  */
/*-----------------------------------------------------------------*/
static void
movLeft2Result (operand * left, int offl,
                operand * result, int offr, int sign)
{
  if (!sameRegs (AOP (left), AOP (result)) || (offl != offr))
    {
      if (!sign)
        cheapMove (AOP (result), offr, AOP (left), offl);
      else
        {
          if (getDataSize (left) == offl + 1)
            {
              cheapMove (ASMOP_A, 0, AOP (left), offl);
              cheapMove (AOP (result), offr, ASMOP_A, 0);
            }
        }
    }
}

static void
movLeft2ResultLong (operand * left, int offl,
                operand * result, int offr, int sign,
                int size)
{
  if (size == 1)
    movLeft2Result (left, offl, result, offr, sign);
  else
    {
      wassertl (offl == 0 && offr == 0, "Only implemented for zero offset");
      wassertl (size == 2, "Only implemented for two bytes or one");

      if ( IS_GB && requiresHL ( AOP (left)) && getPairId ( AOP (result)) == PAIR_HL)
        {
          emit2 ("ld a,%s", aopGet (AOP (left), LSB, FALSE));
          emit2 ("ld h,%s", aopGet (AOP (left), MSB16, FALSE));
          emit2 ("ld l,a");
          spillPair (PAIR_HL);
        }
      else if ( getPairId ( AOP (result)) == PAIR_IY)
        {
          PAIR_ID id = getPairId (AOP (left));
          if (id != PAIR_INVALID)
            {
              emit2("push %s", _pairs[id].name);
              emit2("pop iy");
              regalloc_dry_run_cost += 3;
            }
          else
            {
              fetchPair (PAIR_IY, AOP (left));
            }
        }
      else
        {
          movLeft2Result (left, offl, result, offr, sign);
          movLeft2Result (left, offl+1, result, offr+1, sign);
        }
    }
}

/** Put Acc into a register set
 */
static void
outAcc (operand * result)
{
  int size, offset;
  size = getDataSize (result);
  if (size)
    {
      cheapMove (AOP (result), 0, ASMOP_A, 0);
      size--;
      offset = 1;
      /* unsigned or positive */
      while (size--)
        aopPut3 (AOP (result), offset++, ASMOP_ZERO, 0);
    }
}

/** Take the value in carry and put it into a register
 */
static void
outBitC (operand * result)
{
  /* if the result is bit */
  if (AOP_TYPE (result) == AOP_CRY)
    {
      if (!IS_OP_RUONLY (result) && !regalloc_dry_run)
        aopPut (AOP (result), "c", 0); // Todo: Cost.
    }
  else
    {
      emit2 ("ld a,!zero");
      emit2 ("rla");
      regalloc_dry_run_cost += 3;
      outAcc (result);
    }
}

/*-----------------------------------------------------------------*/
/* toBoolean - emit code for or a,operator(sizeop)                 */
/*-----------------------------------------------------------------*/
static void
_toBoolean (const operand *oper, bool needflag)
{
  int size = AOP_SIZE (oper);
  sym_link *type = operandType (oper);
  int offset = size - 1;

  cheapMove (ASMOP_A, 0, AOP (oper), offset--);
  if (size > 1)
    {
      if (IS_FLOAT (type))
        {
          emit2 ("res 7, a"); //clear sign bit
          regalloc_dry_run_cost += 2;
          while (--size)
            emit3_o (A_OR, ASMOP_A, 0, AOP (oper), offset--);
        }
      else
        {
          while (--size)
            emit3_o (A_OR, ASMOP_A, 0, AOP (oper), offset--);
        }
    }
  else if (needflag)
    {
      emit3 (A_OR, ASMOP_A, ASMOP_A);
    }
}

/*-----------------------------------------------------------------*/
/* castBoolean - emit code for casting operand to boolean in a     */
/*-----------------------------------------------------------------*/
static void
_castBoolean (const operand *right)
{
  emitDebug ("; Casting to bool");

  /* Can do without OR-ing for small arguments */
  if (AOP_SIZE (right)== 1 && AOP_TYPE (right) != AOP_ACC)
    {
      emit3 (A_XOR, ASMOP_A, ASMOP_A);
      emit3 (A_CP, ASMOP_A, AOP (right));
    }
  else
    {
      _toBoolean (right, FALSE);
      emit2 ("add a,!immedbyte", 0xff);
      emit2 ("ld a,!zero");
      regalloc_dry_run_cost += 4;
    }
  emit2 ("rla");
  regalloc_dry_run_cost += 1;
}

/* Shuffle src reg array into dst reg array. */
static void regMove(short *dst, short *src, size_t n)
{
  bool assigned[8] = {FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE};
  int cached_byte = -1;
  size_t size = n;
  
  wassert (n < 6);

  // We need to be able to handle any assignment here, ensuring not to overwrite any parts of the source that we still need.
  while (size--)
    {
      size_t i;
              
      // Find lowest byte that can be assigned and needs to be assigned.
      for (i = 0; i < n; i++)
        {
          size_t j;
                  
          if (assigned[i])
            continue;
                    
          for (j = 0; j < n; j++)
            {
              if (!assigned[j] && i != j && dst[i] == src[j])
                goto skip_byte; // We can't write this one without overwriting the source.
            }
                  
          break; // Found byte that can be written safely.
                  
          skip_byte:;
        }

      if (i < n)
        {
          cheapMove (asmopregs[dst[i]], 0, asmopregs[src[i]], 0); // We can safely assign a byte.
          assigned[i] = TRUE;
          continue;
        }
              
      // No byte can be assigned safely (i.e. the assignment is a permutation). Cache one in the accumulator.
 
      if (cached_byte != -1)
        {
          // Already one cached. Can happen when the assignment is a permutation consisting of multiple cycles.
          cheapMove (asmopregs[dst[cached_byte]], 0, ASMOP_A, 0);
          cached_byte = -1;
          continue;
        }
              
      for (i = 0; i < n; i++)
        if (!assigned[i])
          break;
      wassertl (i != n, "regMove error: Trying to cache non-existant byte in accumulator."); 
      cheapMove (ASMOP_A, 0, asmopregs[src[i]], 0);
      assigned[i] = TRUE;
      cached_byte = i;
    }
           
  if (cached_byte != -1)
    cheapMove (asmopregs[dst[cached_byte]], 0, ASMOP_A, 0);
}

/*-----------------------------------------------------------------*/
/* genNot - generate code for ! operation                          */
/*-----------------------------------------------------------------*/
static void
genNot (const iCode * ic)
{
  operand *left = IC_LEFT(ic);
  operand *result = IC_RESULT(ic);

  /* assign asmOps to operand & result */
  aopOp (left, ic, FALSE, TRUE);
  aopOp (result, ic, TRUE, FALSE);

  /* if in bit space then a special case */
  if (AOP_TYPE (left) == AOP_CRY)
    {
      wassertl (0, "Tried to negate a bit");
    }
  else if (IS_BOOL (operandType (left)))
    {
      cheapMove (ASMOP_A, 0, AOP (left), 0);
      emit2 ("xor a,#0x01");
      regalloc_dry_run_cost += 2;
      cheapMove (AOP (result), 0, ASMOP_A, 0);
      goto release;
    }

  _toBoolean (left, FALSE);

  /* Not of A:
     If A == 0, !A = 1
     else A = 0
     So if A = 0, A-1 = 0xFF and C is set, rotate C into reg. */
  emit2 ("sub a,!one");
  regalloc_dry_run_cost += 2;
  outBitC (result);

release:
  /* release the aops */
  freeAsmop (left, NULL, ic);
  freeAsmop (result, NULL, ic); 
}

/*-----------------------------------------------------------------*/
/* genCpl - generate code for complement                           */
/*-----------------------------------------------------------------*/
static void
genCpl (const iCode *ic)
{
  int offset = 0;
  int size;


  /* assign asmOps to operand & result */
  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);
  aopOp (IC_RESULT (ic), ic, TRUE, FALSE);

  /* if both are in bit space then
     a special case */
  if (AOP_TYPE (IC_RESULT (ic)) == AOP_CRY &&
      AOP_TYPE (IC_LEFT (ic)) == AOP_CRY)
    {
      wassertl (0, "Left and the result are in bit space");
    }

  size = AOP_SIZE (IC_RESULT (ic));
  while (size--)
    {
      cheapMove (ASMOP_A, 0, AOP (IC_LEFT (ic)), offset);
      emit3 (A_CPL, 0, 0);
      cheapMove (AOP (IC_RESULT (ic)), offset++, ASMOP_A, 0);
    }

  /* release the aops */
  freeAsmop (IC_LEFT (ic), NULL, ic);
  freeAsmop (IC_RESULT (ic), NULL, ic);
}

static void
_gbz80_emitAddSubLongLong (const iCode *ic, asmop *left, asmop *right, bool isAdd)
{
  const char *first = isAdd ? "add" : "sub";
  const char *later = isAdd ? "adc" : "sbc";


  wassert (!regalloc_dry_run);

  /* Logic:
       ld de,right.lw
       setup hl to left
       de = hl - de
       push flags
       store de into result
       pop flags
       ld de,right.hw
       setup hl
       de = hl -de
       store de into result
  */

  wassertl (IS_GB, "Code is only relevant to the gbz80");
  wassertl (AOP( IC_RESULT (ic))->size == 4, "Only works for four bytes");

  fetchPair (PAIR_DE, left);

  emit2 ("ld a,e");
  emit2 ("%s a,%s", first, aopGet( right, LSB, FALSE));
  emit2 ("ld e,a");
  emit2 ("ld a,d");
  emit2 ("%s a,%s", later, aopGet( right, MSB16, FALSE));

  _push (PAIR_AF);
  aopPut ( AOP (IC_RESULT (ic)), "a", MSB16);
  aopPut ( AOP (IC_RESULT (ic)), "e", LSB);

  fetchPairLong (PAIR_DE, left, NULL, MSB24);
  aopGet (right, MSB24, FALSE);

  _pop (PAIR_AF);
  emit2 ("ld a,e");
  emit2 ("%s a,%s", later, aopGet( right, MSB24, FALSE));
  emit2 ("ld e,a");
  emit2 ("ld a,d");
  emit2 ("%s a,%s", later, aopGet( right, MSB32, FALSE));

  aopPut ( AOP (IC_RESULT (ic)), "a", MSB32);
  aopPut ( AOP (IC_RESULT (ic)), "e", MSB24);
}

static void
_gbz80_emitAddSubLong (const iCode *ic, bool isAdd)
{
  _gbz80_emitAddSubLongLong (ic, AOP (IC_LEFT (ic)), AOP (IC_RIGHT (ic)), isAdd);
}

/*-----------------------------------------------------------------*/
/* genUminusFloat - unary minus for floating points                */
/*-----------------------------------------------------------------*/
static void
genUminusFloat (operand * op, operand * result)
{
  int size, offset = 0;

  emitDebug("; genUminusFloat");

  /* for this we just need to flip the
     first bit then copy the rest in place */
  size = AOP_SIZE (op) - 1;

  cheapMove (ASMOP_A, 0, AOP (op), MSB32);

  emit2 ("xor a,!immedbyte", 0x80);
  regalloc_dry_run_cost += 2;
  cheapMove (AOP (result), MSB32, ASMOP_A, 0);

  if (operandsEqu (result, op))
    return;

  while (size--)
    {
      cheapMove (AOP (result), offset,AOP (op), offset);
      offset++;
    }
}

/*-----------------------------------------------------------------*/
/* genUminus - unary minus code generation                         */
/*-----------------------------------------------------------------*/
static void
genUminus (const iCode *ic)
{
  int offset, size;
  sym_link *optype;

  /* assign asmops */
  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);
  aopOp (IC_RESULT (ic), ic, TRUE, FALSE);

  /* if both in bit space then special
     case */
  if (AOP_TYPE (IC_RESULT (ic)) == AOP_CRY &&
      AOP_TYPE (IC_LEFT (ic)) == AOP_CRY)
    {
      wassertl (0, "Left and right are in bit space");
      goto release;
    }

  optype = operandType (IC_LEFT (ic));

  /* if float then do float stuff */
  if (IS_FLOAT (optype))
    {
      genUminusFloat (IC_LEFT (ic), IC_RESULT (ic));
      goto release;
    }

  /* otherwise subtract from zero */
  size = AOP_SIZE (IC_LEFT (ic));

  if (AOP_SIZE (IC_RESULT (ic)) == 4 && IS_GB)
    {
      /* Create a new asmop with value zero */
      asmop *azero = newAsmop (AOP_SIMPLELIT);
      azero->aopu.aop_simplelit = 0;
      azero->size = size;
      _gbz80_emitAddSubLongLong (ic, azero, AOP (IC_LEFT (ic)), FALSE);
      goto release;
    }

  offset = 0;

  _clearCarry();
  while (size--)
    {
      emit3 (A_LD, ASMOP_A, ASMOP_ZERO);
      emit3_o (A_SBC, ASMOP_A, 0, AOP (IC_LEFT (ic)), offset);
      cheapMove (AOP (IC_RESULT (ic)), offset++, ASMOP_A, 0);
    }

  /* if any remaining bytes in the result */
  /* we just need to propagate the sign   */
  if ((size = (AOP_SIZE (IC_RESULT (ic)) - AOP_SIZE (IC_LEFT (ic)))))
    {
      emit3 (A_RLC, ASMOP_A, 0);
      emit3 (A_SBC, ASMOP_A, ASMOP_A);
      while (size--)
        cheapMove (AOP (IC_RESULT (ic)), offset++, ASMOP_A, 0);
    }

release:
  /* release the aops */
  freeAsmop (IC_LEFT (ic), NULL, ic);
  freeAsmop (IC_RESULT (ic), NULL, ic);
}

/*-----------------------------------------------------------------*/
/* assignResultValue -               */
/*-----------------------------------------------------------------*/
static void
assignResultValue (operand * oper)
{
  int size = AOP_SIZE (oper);

  wassertl (size <= 4, "Got a result that is bigger than four bytes");

  if (IS_GB && size == 4 && requiresHL (AOP (oper)))
    {
      /* We do it the hard way here. */
      _push (PAIR_HL);
      aopPut (AOP (oper), _fReturn[0], 0);
      aopPut (AOP (oper), _fReturn[1], 1);
      _pop (PAIR_DE);
      aopPut (AOP (oper), _fReturn[0], 2);
      aopPut (AOP (oper), _fReturn[1], 3);
    }
  else
    {
      if (AOP_TYPE (oper) == AOP_REG)
        {
          int i;
          short retarray[4], oparray[4];
          
          for(i = 0; i < size; i++)
          {
             retarray[i] = _fReturn3[i]->aopu.aop_reg[0]->rIdx;
             oparray[i] = AOP (oper)->aopu.aop_reg[i]->rIdx;
          }
          
          regMove(oparray, retarray, size);
        }
      else
        while (size--)
          cheapMove (AOP (oper), size, _fReturn3[size], 0);
    }
}

/** Simple restore that doesn't take into account what is used in the
    return.
*/
static void
_restoreRegsAfterCall(void)
{
  if (_G.stack.pushedDE)
    {
      _pop ( PAIR_DE);
      _G.stack.pushedDE = FALSE;
    }
  if (_G.stack.pushedBC)
    {
      _pop ( PAIR_BC);
      _G.stack.pushedBC = FALSE;
    }
  if (_G.stack.pushedIY)
    {
      _pop ( PAIR_IY);
      _G.stack.pushedIY = FALSE;
    }
  _G.saves.saved = FALSE;
}

static void
_saveRegsForCall(const iCode *ic, int sendSetSize, bool dontsaveIY)
{
  /* Rules:
      o Stack parameters are pushed before this function enters
      o DE and BC may be used in this function.
      o HL and DE may be used to return the result.
      o HL and DE may be used to send variables.
      o DE and BC may be used to store the result value.
      o HL may be used in computing the sent value of DE
      o The iPushes for other parameters occur before any addSets

     Logic: (to be run inside the first iPush or if none, before sending)
      o Compute if DE and/or BC are in use over the call
      o Compute if DE is used in the send set
      o Compute if DE and/or BC are used to hold the result value
      o If (DE is used, or in the send set) and is not used in the result, push.
      o If BC is used and is not in the result, push
      o
      o If DE is used in the send set, fetch
      o If HL is used in the send set, fetch
      o Call
      o ...
  */
  
  if (_G.saves.saved == FALSE) {
    bool push_bc, push_de, push_iy;
    
    if(z80_opts.oldralloc)
      {
        bool deInUse, bcInUse;
        bool deSending;
        bool bcInRet = FALSE, deInRet = FALSE;
        bitVect *rInUse;

        rInUse = bitVectCplAnd (bitVectCopy (ic->rMask), z80_rUmaskForOp (IC_RESULT(ic)));

        deInUse = bitVectBitValue (rInUse, D_IDX) || bitVectBitValue(rInUse, E_IDX);
        bcInUse = bitVectBitValue (rInUse, B_IDX) || bitVectBitValue(rInUse, C_IDX);

        deSending = (sendSetSize > 1);

        emitDebug ("; _saveRegsForCall: sendSetSize: %u deInUse: %u bcInUse: %u deSending: %u", sendSetSize, deInUse, bcInUse, deSending);

        push_bc = bcInUse && !bcInRet;
        push_de = deInUse && !deInRet;
        push_iy = FALSE;
      }
    else
      {
        push_bc = bitVectBitValue (ic->rSurv, B_IDX) || bitVectBitValue (ic->rSurv, C_IDX);
        push_de = bitVectBitValue (ic->rSurv, D_IDX) || bitVectBitValue (ic->rSurv, E_IDX);
        push_iy = !dontsaveIY && (bitVectBitValue (ic->rSurv, IYH_IDX) || bitVectBitValue (ic->rSurv, IYL_IDX));
      }

    if (push_bc) {
      _push(PAIR_BC);
      _G.stack.pushedBC = TRUE;
    }
    if (push_de) {
      _push(PAIR_DE);
      _G.stack.pushedDE = TRUE;
    }
    if (push_iy) {
      _push(PAIR_IY);
      _G.stack.pushedIY = TRUE;
    }

    if(!regalloc_dry_run)
      _G.saves.saved = TRUE;
  }
  else {
    /* Already saved. */
  }
}

/*-----------------------------------------------------------------*/
/* genIpush - genrate code for pushing this gets a little complex  */
/*-----------------------------------------------------------------*/
static void
genIpush (const iCode * ic)
{
  int size, offset = 0;

  /* if this is not a parm push : ie. it is spill push
     and spill push is always done on the local stack */
  if (!ic->parmPush)
    {
      wassertl(0, "Encountered an unsupported spill push.");
      return;
    }

  if (_G.saves.saved == FALSE && !regalloc_dry_run /* Cost is counted at CALL or PCALL instead */) {
    /* Caller saves, and this is the first iPush. */
    /* Scan ahead until we find the function that we are pushing parameters to.
       Count the number of addSets on the way to figure out what registers
       are used in the send set.
    */
    int nAddSets = 0;
    iCode *walk = ic->next;

    while (walk) {
      if (walk->op == SEND) {
        nAddSets++;
      }
      else if (walk->op == CALL || walk->op == PCALL) {
        /* Found it. */
        break;
      }
      else {
        /* Keep looking. */
      }
      walk = walk->next;
    }
    _saveRegsForCall(walk, nAddSets, FALSE);
  }

  /* then do the push */
  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);

  size = AOP_SIZE (IC_LEFT (ic));

  if (isPair (AOP (IC_LEFT (ic))) && size == 2)
    {
      if(!regalloc_dry_run)
        {
           _G.stack.pushed += 2;
           emit2 ("push %s", getPairName (AOP (IC_LEFT (ic))));
        }
      regalloc_dry_run_cost += (getPairId (AOP (IC_LEFT (ic))) == PAIR_IY ? 2 : 1);
    }
  else
    {
      if (size == 2)
        {
          fetchHL (AOP (IC_LEFT (ic)));
          if(!regalloc_dry_run)
            {
              emit2 ("push hl");
              _G.stack.pushed += 2;
            }
          regalloc_dry_run_cost += 1;
          goto release;
        }
      if (size == 4)
        {
          if (AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[2]->rIdx == C_IDX && AOP (IC_LEFT (ic))->aopu.aop_reg[3]->rIdx == B_IDX)
            {
              emit2 ("push bc");
              regalloc_dry_run_cost += 1;
            }
          else if (AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[2]->rIdx == E_IDX && AOP (IC_LEFT (ic))->aopu.aop_reg[3]->rIdx == D_IDX)
            {
              emit2 ("push de");
              regalloc_dry_run_cost += 1;
            }
          else
            {
              fetchPairLong (PAIR_HL, AOP (IC_LEFT (ic)), ic, 2);
              emit2 ("push hl");
              regalloc_dry_run_cost += 1;
            }
          if (!regalloc_dry_run)
            _G.stack.pushed += 2;
          
          if (AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == C_IDX && AOP (IC_LEFT (ic))->aopu.aop_reg[1]->rIdx == B_IDX)
            {
              emit2 ("push bc");
              regalloc_dry_run_cost += 1;
            }
          else if (AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == E_IDX && AOP (IC_LEFT (ic))->aopu.aop_reg[1]->rIdx == D_IDX)
            {
              emit2 ("push de");
              regalloc_dry_run_cost += 1;
            }
          else
            {
              fetchPairLong (PAIR_HL, AOP (IC_LEFT (ic)), ic, 0);
              emit2 ("push hl");
              regalloc_dry_run_cost += 1;
            }
          if (!regalloc_dry_run)
            _G.stack.pushed += 2;
            
          goto release;
        }
      offset = size;
      while (size--)
        {
          if (AOP (IC_LEFT (ic))->type == AOP_IY)
            {
              emit2 ("ld a,(%s)", aopGetLitWordLong (AOP (IC_LEFT (ic)), --offset, FALSE));
              emit2 ("push af");
              regalloc_dry_run_cost += 4;
            }
          else
            {
              offset--;
              if (AOP (IC_LEFT (ic))->type == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[offset]->rIdx == B_IDX)
                {
                  emit2 ("push bc");
                  regalloc_dry_run_cost += 1;
                }
              else if (AOP (IC_LEFT (ic))->type == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[offset]->rIdx == D_IDX)
                {
                  emit2 ("push de");
                  regalloc_dry_run_cost += 1;
                }
              else
                {
                  if (!regalloc_dry_run && !strcmp(aopGet (AOP (IC_LEFT (ic)), offset, FALSE), "h")) // todo: More exact cost!
                    emit2 ("push hl");
                  else
                    {
                      cheapMove (ASMOP_A, 0, AOP (IC_LEFT (ic)), offset);
                      emit2 ("push af");
                    }
                  regalloc_dry_run_cost += (ld_cost(ASMOP_A, AOP (IC_LEFT (ic))) + 1);
                }
            }
          if (!regalloc_dry_run)
            {
              emit2 ("inc sp");
              _G.stack.pushed++;
            }
          regalloc_dry_run_cost += 1;
        }
    }
release:
  freeAsmop (IC_LEFT (ic), NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genIpop - recover the registers: can happen only for spilling   */
/*-----------------------------------------------------------------*/
static void
genIpop (const iCode * ic)
{
  int size, offset;

  wassert (!regalloc_dry_run);

  /* if the temp was not pushed then */
  if (OP_SYMBOL (IC_LEFT (ic))->isspilt)
    return;

  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);
  size = AOP_SIZE (IC_LEFT (ic));
  offset = (size - 1);
  if (isPair (AOP (IC_LEFT (ic))))
    {
      emit2 ("pop %s", getPairName (AOP (IC_LEFT (ic))));
    }
  else
    {
      while (size--)
        {
          emit2 ("dec sp");
          emit2 ("pop hl");
          spillPair (PAIR_HL);
          aopPut (AOP (IC_LEFT (ic)), "l", offset--);
        }
    }

  freeAsmop (IC_LEFT (ic), NULL, ic);
}

/* This is quite unfortunate */
static void
setArea (int inHome)
{
  /*
    static int lastArea = 0;

     if (_G.in_home != inHome) {
     if (inHome) {
     const char *sz = port->mem.code_name;
     port->mem.code_name = "HOME";
     emit2("!area", CODE_NAME);
     port->mem.code_name = sz;
     }
     else
     emit2("!area", CODE_NAME); */
  _G.in_home = inHome;
  //    }
}

static bool
isInHome (void)
{
  return _G.in_home;
}

static int
_opUsesPair (operand * op, const iCode * ic, PAIR_ID pairId)
{
  int ret = 0;
  asmop *aop;
  symbol *sym = OP_SYMBOL (op);

  if (sym->isspilt || sym->nRegs == 0)
    return 0;

  aopOp (op, ic, FALSE, FALSE);

  aop = AOP (op);
  if (aop->type == AOP_REG)
    {
      int i;
      for (i = 0; i < aop->size; i++)
        {
          if (pairId == PAIR_DE)
            {
              emitDebug ("; name %s", aop->aopu.aop_reg[i]->name);
              if (!strcmp (aop->aopu.aop_reg[i]->name, "e"))
                ret++;
              if (!strcmp (aop->aopu.aop_reg[i]->name, "d"))
                ret++;
            }
          else if (pairId == PAIR_BC)
            {
              emitDebug ("; name %s", aop->aopu.aop_reg[i]->name);
              if (!strcmp (aop->aopu.aop_reg[i]->name, "c"))
                ret++;
              if (!strcmp (aop->aopu.aop_reg[i]->name, "b"))
                ret++;
            }
          else
            {
              wassert (0);
            }
        }
    }

  freeAsmop (IC_LEFT (ic), NULL, ic);
  return ret;
}

/** Emit the code for a call statement
 */
static void
emitCall (const iCode *ic, bool ispcall)
{
  bool bInRet, cInRet, dInRet, eInRet;
  sym_link *dtype = operandType (IC_LEFT (ic));
  sym_link *etype = getSpec(dtype);

  /* if caller saves & we have not saved then */
  if (!ic->regsSaved)
    {
      /* PENDING */
    }

  _saveRegsForCall(ic, _G.sendSet ? elementsInSet(_G.sendSet) : 0, FALSE);

  /* if send set is not empty then assign */
  if (_G.sendSet)
    {
      iCode *sic;
      int send = 0;
      int nSend = elementsInSet(_G.sendSet);
      bool swapped = FALSE;

      int _z80_sendOrder[] = {
        PAIR_BC, PAIR_DE
      };

      if (nSend > 1) {
        /* Check if the parameters are swapped.  If so route through hl instead. */
        wassertl (nSend == 2, "Pedantic check.  Code only checks for the two send items case.");

        sic = setFirstItem(_G.sendSet);
        sic = setNextItem(_G.sendSet);

        if (_opUsesPair (IC_LEFT(sic), sic, _z80_sendOrder[0])) {
          /* The second send value is loaded from one the one that holds the first
             send, i.e. it is overwritten. */
          /* Cache the first in HL, and load the second from HL instead. */
          emit2 ("ld h,%s", _pairs[_z80_sendOrder[0]].h);
          emit2 ("ld l,%s", _pairs[_z80_sendOrder[0]].l);
          regalloc_dry_run_cost += 2;

          swapped = TRUE;
        }
      }

      for (sic = setFirstItem (_G.sendSet); sic;
           sic = setNextItem (_G.sendSet))
        {
          int size;
          aopOp (IC_LEFT (sic), sic, FALSE, FALSE);

          size = AOP_SIZE (IC_LEFT (sic));
          wassertl (size <= 2, "Tried to send a parameter that is bigger than two bytes");
          wassertl (_z80_sendOrder[send] != PAIR_INVALID, "Tried to send more parameters than we have registers for");

          // PENDING: Mild hack
          if (swapped == TRUE && send == 1) {
            if (size > 1) {
              emit2 ("ld %s,h", _pairs[_z80_sendOrder[send]].h);
              regalloc_dry_run_cost += 1;
            }
            else {
              emit2 ("ld %s,!zero", _pairs[_z80_sendOrder[send]].h);
              regalloc_dry_run_cost += 2;
            }
            emit2 ("ld %s,l", _pairs[_z80_sendOrder[send]].l);
            regalloc_dry_run_cost += 1;
          }
          else {
            fetchPair(_z80_sendOrder[send], AOP (IC_LEFT (sic)));
          }

          send++;
          freeAsmop (IC_LEFT (sic), NULL, sic);
        }
      _G.sendSet = NULL;
    }

  if (ispcall)
    {
      if (IFFUNC_ISBANKEDCALL (dtype))
        {
          werror (W_INDIR_BANKED);
        }
      aopOp (IC_LEFT (ic), ic, FALSE, FALSE);

      if (isLitWord (AOP (IC_LEFT (ic))))
        {
          emit2 ("call %s", aopGetLitWordLong (AOP (IC_LEFT (ic)), 0, FALSE));
          regalloc_dry_run_cost += 3;
        }
      else
        {
          spillPair (PAIR_HL);
          fetchHL (AOP (IC_LEFT (ic)));
          emit2 ("call __sdcc_call_hl");
        }
      freeAsmop (IC_LEFT (ic), NULL, ic);
    }
  else
    {
      /* make the call */
      if (IFFUNC_ISBANKEDCALL (dtype))
        {
          char *name = OP_SYMBOL (IC_LEFT (ic))->rname[0] ?
                       OP_SYMBOL (IC_LEFT (ic))->rname :
                       OP_SYMBOL (IC_LEFT (ic))->name;
          emit2 ("call banked_call");
          emit2 ("!dws", name);
          emit2 ("!dw !bankimmeds", name);
          regalloc_dry_run_cost += 6;
        }
      else
        {
          if (IS_LITERAL (etype))
            {
              emit2 ("call 0x%04X", ulFromVal (OP_VALUE (IC_LEFT (ic))));
              regalloc_dry_run_cost += 3;
            }
          else
            {
              emit2 ("call %s", (OP_SYMBOL (IC_LEFT (ic))->rname[0] ?
                                 OP_SYMBOL (IC_LEFT (ic))->rname :
                                 OP_SYMBOL (IC_LEFT (ic))->name));
              regalloc_dry_run_cost += 3;
            }
        }
    }
  spillCached ();

  /* Mark the registers as restored. */
  _G.saves.saved = FALSE;

  /* adjust the stack for parameters if required */
  if (ic->parmBytes)
    {
      int i = ic->parmBytes;

      if (!regalloc_dry_run)
        _G.stack.pushed -= i;
      if (IS_GB)
        {
          emit2 ("!ldaspsp", i);
        }
      else
        {
          spillCached ();
          if (IS_R2K ? i > 127 * 4 - 1 : i > 8)
            {
              emit2 ("ld iy,!immedword", i);
              emit2 ("add iy,sp");
              emit2 ("ld sp,iy");
              regalloc_dry_run_cost += 8;
            }
          else
            {

              while (i > 1)
                {
                  if (IS_R2K && (!optimize.codeSize || i > 2))
                    {
                      int d = (i < 127 ? i : 127);
                      emit2 ("add sp, #%d", d);
                      regalloc_dry_run_cost += 2;
                      i -= d;
                    }
                  else
                    {
                      emit2 ("pop af");
                      regalloc_dry_run_cost += 1;
                      i -= 2;
                    }
                }
              if (i)
                {
                  emit2 ("inc sp");
                  regalloc_dry_run_cost += 1;
                }
            }
        }
    }

  /* if we need assign a result value */
  if ((IS_ITEMP (IC_RESULT (ic)) &&
       (OP_SYMBOL (IC_RESULT (ic))->nRegs ||
        OP_SYMBOL (IC_RESULT (ic))->spildir ||
        OP_SYMBOL (IC_RESULT (ic))->accuse == ACCUSE_A)) ||
      IS_TRUE_SYMOP (IC_RESULT (ic)))
    {
      aopOp (IC_RESULT (ic), ic, FALSE, FALSE);

      assignResultValue (IC_RESULT (ic));

      freeAsmop (IC_RESULT (ic), NULL, ic);
    }

  spillCached ();
  
  if (IC_RESULT (ic))
    {
      bitVect *result = z80_rUmaskForOp (IC_RESULT (ic));
      bInRet = bitVectBitValue(result, B_IDX);
      cInRet = bitVectBitValue(result, C_IDX);
      dInRet = bitVectBitValue(result, D_IDX);
      eInRet = bitVectBitValue(result, E_IDX);
    }
  else
    {
      bInRet = FALSE;
      cInRet = FALSE;
      dInRet = FALSE;
      eInRet = FALSE;
    }

  if (_G.stack.pushedIY)
    {
      _pop (PAIR_IY);
      _G.stack.pushedIY = FALSE;
    }

  if (_G.stack.pushedDE)
    {
      if (dInRet && eInRet)
        {
          wassertl (0, "Shouldn't push DE if it's wiped out by the return");
        }
      else if (dInRet)
        {
          /* Only restore E */
          emit2 ("ld a,d");
          regalloc_dry_run_cost += 1;
          _pop (PAIR_DE);
          emit2 ("ld d,a");
          regalloc_dry_run_cost += 1;
        }
      else if (eInRet)
        {
          /* Only restore D */
          _pop (PAIR_AF);
          emit2 ("ld d,a");
          regalloc_dry_run_cost += 1;
        }
      else
        {
          _pop (PAIR_DE);
        }
      _G.stack.pushedDE = FALSE;
    }

  if (_G.stack.pushedBC)
    {
      if (bInRet && cInRet)
        {
          wassertl (0, "Shouldn't push BC if it's wiped out by the return");
        }
      else if (bInRet)
        {
          /* Only restore C */
          emit2 ("ld a,b");
          regalloc_dry_run_cost += 1;
          _pop (PAIR_BC);
          emit2 ("ld b,a");
          regalloc_dry_run_cost += 1;
        }
      else if (cInRet)
        {
          /* Only restore B */
          _pop (PAIR_AF);
          emit2 ("ld b,a");
          regalloc_dry_run_cost += 1;
        }
      else
        {
          _pop (PAIR_BC);
        }
      _G.stack.pushedBC = FALSE;
    }
}

/*-----------------------------------------------------------------*/
/* genCall - generates a call statement                            */
/*-----------------------------------------------------------------*/
static void
genCall (const iCode *ic)
{
  emitCall (ic, FALSE);
}

/*-----------------------------------------------------------------*/
/* genPcall - generates a call by pointer statement                */
/*-----------------------------------------------------------------*/
static void
genPcall (const iCode *ic)
{
  emitCall (ic, TRUE);
}

/*-----------------------------------------------------------------*/
/* resultRemat - result  is rematerializable                       */
/*-----------------------------------------------------------------*/
static int
resultRemat (const iCode *ic)
{
  if (SKIP_IC (ic) || ic->op == IFX)
    return 0;

  if (IC_RESULT (ic) && IS_ITEMP (IC_RESULT (ic)))
    {
      const symbol *sym = OP_SYMBOL_CONST (IC_RESULT (ic));
      if (sym->remat && !POINTER_SET (ic) && sym->isspilt)
        return 1;
    }

  return 0;
}

/*-----------------------------------------------------------------*/
/* genFunction - generated code for function entry                 */
/*-----------------------------------------------------------------*/
static void
genFunction (const iCode * ic)
{
  bool stackParm;

  symbol *sym = OP_SYMBOL (IC_LEFT (ic));
  sym_link *ftype;

  bool bcInUse = FALSE;
  bool deInUse = FALSE;

  setArea (IFFUNC_NONBANKED (sym->type));

  /* PENDING: Reset the receive offset as it
     doesn't seem to get reset anywhere else.
  */
  _G.receiveOffset = 0;

  /* Record the last function name for debugging. */
  _G.lastFunctionName = sym->rname;

  /* Create the function header */
  emit2 ("!functionheader", sym->name);

  emitDebug(assignment_optimal ? "; Register assignment is optimal." : "; Register assignment might be sub-optimal.");
  emitDebug("; Stack space usage: %d bytes.", sym->stack);

  if (!IS_STATIC(sym->etype))
    {
      struct dbuf_s dbuf;

      dbuf_init (&dbuf, 128);
      dbuf_printf (&dbuf, "%s_start", sym->rname);
      emit2 ("!labeldef", dbuf_c_str (&dbuf));
      dbuf_detach (&dbuf);
      if(!regalloc_dry_run)
       _G.lines.current->isLabel = 1;
    }
  emit2 ("!functionlabeldef", sym->rname);
  if(!regalloc_dry_run)
    _G.lines.current->isLabel = 1;

  ftype = operandType (IC_LEFT (ic));

  if (IFFUNC_ISNAKED(ftype))
    {
      emitDebug("; naked function: no prologue.");
      return;
    }

  /* if this is an interrupt service routine
     then save all potentially used registers. */
  if (IFFUNC_ISISR (sym->type))
    {
      if (IS_R2K)
        emit2 ("push ip");
      
      /* If critical function then turn interrupts off */
      /* except when no interrupt number is given then it implies the NMI handler */
      if (IFFUNC_ISCRITICAL (sym->type) && (FUNC_INTNO(sym->type) != INTNO_UNSPEC))
        {
          emit2 ("!di");
        }

      emit2 ("!pusha");
    }
  else
    {
      /* This is a non-ISR function.
         If critical function then turn interrupts off */
      if (IFFUNC_ISCRITICAL (sym->type))
        {
          if (IS_GB || IS_R2K)
            {
              emit2 ("!di");
            }
          else
            {
              //get interrupt enable flag IFF2 into P/O
              emit2 ("ld a,i");
              emit2 ("!di");
              //save P/O flag
              emit2 ("push af");
            }
        }
    }

  if (options.profile)
    {
      emit2 ("!profileenter");
    }

  /* PENDING: callee-save etc */

  _G.stack.param_offset = 0;

  if (z80_opts.calleeSavesBC)
    {
      bcInUse = TRUE;
    }

  /* Detect which registers are used. */
  if (IFFUNC_CALLEESAVES(sym->type) && sym->regsUsed)
    {
      int i;
      for (i = 0; i < sym->regsUsed->size; i++)
        {
          if (bitVectBitValue (sym->regsUsed, i))
            {
              switch (i)
                {
                case C_IDX:
                case B_IDX:
                  bcInUse = TRUE;
                  break;
                case D_IDX:
                case E_IDX:
                  if (!IS_GB) {
                    deInUse = TRUE;
                  }
                  else {
                    /* Other systems use DE as a temporary. */
                  }
                  break;
                }
            }
        }
    }

  if (bcInUse)
    {
      emit2 ("push bc");
      _G.stack.param_offset += 2;
    }

  _G.calleeSaves.pushedBC = bcInUse;

  if (deInUse)
    {
      emit2 ("push de");
      _G.stack.param_offset += 2;
    }

  _G.calleeSaves.pushedDE = deInUse;

  /* adjust the stack for the function */
//  _G.stack.last = sym->stack;

  stackParm = FALSE;
  for (sym = setFirstItem (istack->syms); sym;
       sym = setNextItem (istack->syms))
    {
      if (sym->_isparm && !IS_REGPARM (sym->etype))
        {
          stackParm = TRUE;
          break;
        }
    }
  sym = OP_SYMBOL (IC_LEFT (ic));

  _G.omitFramePtr = (!IS_GB && options.omitFramePtr);

  if (!IS_GB && !IY_RESERVED && !stackParm && !sym->stack)
    {
      /* When the conflicts between AOP_EXSTK && AOP_HLREG are fixed, */
      /* the above !sym->stack condition can be removed. -- EEP       */
      if (sym->stack)
        emit2 ("!ldaspsp", -sym->stack);
      if(!regalloc_dry_run)
        _G.omitFramePtr = TRUE;
    }
  else if (sym->stack && IS_GB && sym->stack > -INT8MIN)
    emit2 ("!enterxl", sym->stack);
  else if (sym->stack && IY_RESERVED && sym->stack > -INT8MIN)
    emit2 ("!enterx", sym->stack);
  else if (sym->stack)
    {
      if ((optimize.codeSize && sym->stack <= 8) || sym->stack <= 4 || IS_R2K && sym->stack <= 254)
        {
          int stack = sym->stack;
          if (!_G.omitFramePtr)
            emit2 ("!enter");
          while (stack > 1)
            {
              if (IS_R2K && (!optimize.codeSize || stack > 2))
                {
                  int d = (stack < 127 ? -stack : -127);
                  emit2 ("add sp, #%d", d);
                  stack += d;
                }
              else
                {
                  emit2 ("push af");
                  stack -= 2;
                }
            }
          if(stack > 0)
            emit2 ("dec sp");
        }
      else
        {
          if (_G.omitFramePtr)
            emit2 ("!ldaspsp", -sym->stack);
          else
            emit2 ("!enterx", sym->stack);
        }
    }
  else if(!_G.omitFramePtr)
    {
      if (!_G.omitFramePtr)
        emit2 ("!enter");
    }

  _G.stack.offset = sym->stack;
}

/*-----------------------------------------------------------------*/
/* genEndFunction - generates epilogue for functions               */
/*-----------------------------------------------------------------*/
static void
genEndFunction (iCode * ic)
{
  symbol *sym = OP_SYMBOL (IC_LEFT (ic));

  wassert (!regalloc_dry_run);

  if (IFFUNC_ISNAKED(sym->type))
    {
      emitDebug("; naked function: no epilogue.");
      if (!IS_STATIC(sym->etype))
        {
          struct dbuf_s dbuf;

          dbuf_init (&dbuf, 128);
          dbuf_printf (&dbuf, "%s_end", sym->rname);
          emit2 ("!labeldef", dbuf_c_str (&dbuf));
          dbuf_destroy (&dbuf);
          _G.lines.current->isLabel = 1;
        }
      return;
    }

  /* PENDING: calleeSave */
  if (!IS_GB && _G.omitFramePtr)
    {
      if (_G.stack.offset)
        emit2 ("!ldaspsp", _G.stack.offset);
    }
  else if (_G.stack.offset && IS_GB && _G.stack.offset > INT8MAX)
    {
      emit2 ("!leavexl", _G.stack.offset);
    }
  else if (_G.stack.offset)
    {
      emit2 ("!leavex", _G.stack.offset);
    }
  else
    {
      emit2 ("!leave");
    }

  if (_G.calleeSaves.pushedDE)
    {
      emit2 ("pop de");
      _G.calleeSaves.pushedDE = FALSE;
    }

  if (_G.calleeSaves.pushedBC)
    {
      emit2 ("pop bc");
      _G.calleeSaves.pushedBC = FALSE;
    }

  if (options.profile)
    {
      emit2 ("!profileexit");
    }

  /* if this is an interrupt service routine
     then save all potentially used registers. */
  if (IFFUNC_ISISR (sym->type))
    {
      emit2 ("!popa");

      /* If critical function then turn interrupts back on */
      /* except when no interrupt number is given then it implies the NMI handler */
      if (IFFUNC_ISCRITICAL (sym->type) && (FUNC_INTNO(sym->type) != INTNO_UNSPEC))
        {
          emit2 ("!ei");
        }
    }
  else
    {
      /* This is a non-ISR function.
         If critical function then turn interrupts back on */
      if (IFFUNC_ISCRITICAL (sym->type))
        {
          if (IS_GB)
              emit2 ("!ei");
          else if (IS_R2K)
            emit2( "ipres" );
          else
            {
              symbol *tlbl = newiTempLabel (NULL);
              //restore P/O flag
              emit2 ("pop af");
              //parity odd <==> P/O=0 <==> interrupt enable flag IFF2 was 0 <==>
              //don't enable interrupts as they were off before
              emit2 ("jp PO,!tlabel", tlbl->key + 100);
              emit2 ("!ei");
              emit2 ("!tlabeldef", (tlbl->key + 100));
              _G.lines.current->isLabel = 1;
            }
        }
    }

  if (options.debug && currFunc)
    {
      debugFile->writeEndFunction (currFunc, ic, 1);
    }

  if (IFFUNC_ISISR (sym->type))
    {
      /* "critical interrupt" is used to imply NMI handler */
      if (!IS_GB && IFFUNC_ISCRITICAL (sym->type) && FUNC_INTNO(sym->type) == INTNO_UNSPEC)
        emit2 ("retn");
      else if (IS_R2K && IFFUNC_ISCRITICAL (sym->type) && FUNC_INTNO(sym->type) == INTNO_UNSPEC)
        {
          // ISR exit sequence that works on the rabbit 4000
          emit2 ("pop ip");
          emit2 ("ipres");
          emit2 ("ret");
        }
      else
        emit2 ("reti");
    }
  else
    {
      /* Both banked and non-banked just ret */
      emit2 ("ret");
    }

  if (!IS_STATIC(sym->etype))
    {
      struct dbuf_s dbuf;

      dbuf_init (&dbuf, 128);
      dbuf_printf (&dbuf, "%s_end", sym->rname);
      emit2 ("!labeldef", dbuf_c_str (&dbuf));
      dbuf_destroy (&dbuf);
      _G.lines.current->isLabel = 1;
    }

  _G.flushStatics = 1;
  _G.stack.pushed = 0;
  _G.stack.offset = 0;
}

/*-----------------------------------------------------------------*/
/* genRet - generate code for return statement                     */
/*-----------------------------------------------------------------*/
static void
genRet (const iCode *ic)
{
  /* Errk.  This is a hack until I can figure out how
     to cause dehl to spill on a call */
  int size, offset = 0;

  /* if we have no return value then
     just generate the "ret" */
  if (!IC_LEFT (ic))
    goto jumpret;

  /* we have something to return then
     move the return value into place */
  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);
  size = AOP_SIZE (IC_LEFT (ic));

  if (size==2)
    {
      fetchPair(IS_GB ? PAIR_DE : PAIR_HL, AOP (IC_LEFT (ic)));
    }
  else
    {
      if (IS_GB && size == 4 && requiresHL (AOP (IC_LEFT (ic))))
        {
          fetchPair (PAIR_DE, AOP (IC_LEFT (ic)));
          fetchPairLong (PAIR_HL, AOP (IC_LEFT (ic)), ic, 2);
        }
      else if (AOP_TYPE (IC_LEFT (ic)) == AOP_REG)
        {
          int i;
          short retarray[4], oparray[4];
          
          for(i = 0; i < AOP_SIZE (IC_LEFT (ic)); i++)
          {
             retarray[i] = _fReturn3[i]->aopu.aop_reg[0]->rIdx;
             oparray[i] = AOP (IC_LEFT (ic))->aopu.aop_reg[i]->rIdx;
          }
             
          regMove(retarray, oparray, AOP_SIZE (IC_LEFT (ic)));
        }
      else
        {
          while (size--)
            {
              cheapMove (_fReturn3[offset], 0, AOP (IC_LEFT (ic)), offset);
              offset++;
            }
        }
    }
  freeAsmop (IC_LEFT (ic), NULL, ic);

jumpret:
  /* generate a jump to the return label
     if the next is not the return statement */
  if (!(ic->next && ic->next->op == LABEL &&
        IC_LABEL (ic->next) == returnLabel))
    {
      if(!regalloc_dry_run)
        emit2 ("jp !tlabel", returnLabel->key + 100);
      regalloc_dry_run_cost += 3;
    }
}

/*-----------------------------------------------------------------*/
/* genLabel - generates a label                                    */
/*-----------------------------------------------------------------*/
static void
genLabel (const iCode *ic)
{
  /* special case never generate */
  if (IC_LABEL (ic) == entryLabel)
    return;

  emitLabel (IC_LABEL (ic)->key + 100);
}

/*-----------------------------------------------------------------*/
/* genGoto - generates a ljmp                                      */
/*-----------------------------------------------------------------*/
static void
genGoto (const iCode *ic)
{
  emit2 ("jp !tlabel", IC_LABEL (ic)->key + 100);
}

/*-----------------------------------------------------------------*/
/* genPlusIncr :- does addition with increment if possible         */
/*-----------------------------------------------------------------*/
static bool
genPlusIncr (const iCode *ic)
{
  unsigned int icount;
  unsigned int size = getDataSize (IC_RESULT (ic));
  PAIR_ID resultId = getPairId (AOP (IC_RESULT (ic)));

  /* will try to generate an increment */
  /* if the right side is not a literal
     we cannot */
  if (AOP_TYPE (IC_RIGHT (ic)) != AOP_LIT)
    return FALSE;

  emitDebug ("; genPlusIncr");

  icount = (unsigned int) ulFromVal (AOP (IC_RIGHT (ic))->aopu.aop_lit);

  /* If result is a pair */
  if (resultId != PAIR_INVALID)
    {
      if (isLitWord (AOP (IC_LEFT (ic))))
        {
          fetchLitPair (getPairId (AOP (IC_RESULT (ic))), AOP (IC_LEFT (ic)), icount);
          return TRUE;
        }
      if (isPair (AOP (IC_LEFT (ic))) && resultId == PAIR_HL && icount > 3)
        {
          if (getPairId (AOP (IC_LEFT (ic))) == PAIR_HL)
            {
              PAIR_ID freep = getDeadPairId (ic);
              if (freep != PAIR_INVALID)
                {
                  fetchPair (freep, AOP (IC_RIGHT (ic)));
                  emit2 ("add hl,%s", _pairs[freep].name);
                  regalloc_dry_run_cost += 1;
                  return TRUE;
                }
            }
          else
            {
              fetchPair (resultId, AOP (IC_RIGHT (ic)));
              emit2 ("add hl,%s", getPairName (AOP (IC_LEFT (ic))));
              regalloc_dry_run_cost += 1;
              return TRUE;
            }
        }
      if (icount > 5)
        return FALSE;
      /* Inc a pair */
      if (!sameRegs (AOP (IC_LEFT (ic)), AOP (IC_RESULT (ic))))
        {
          if (icount > 3)
            return FALSE;
          movLeft2ResultLong (IC_LEFT (ic), 0, IC_RESULT (ic), 0, 0, 2);
        }
      while (icount--)
        {
          emit2 ("inc %s", getPairName (AOP (IC_RESULT (ic))));
          regalloc_dry_run_cost += (getPairId (AOP (IC_RESULT (ic))) == PAIR_IY ? 2 : 1);
        }
      return TRUE;
    }

  if (!IS_GB && isLitWord (AOP (IC_LEFT (ic))) && size == 2)
    {
      fetchLitPair (PAIR_HL, AOP (IC_LEFT (ic)), icount);
      commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
      return TRUE;
    }

  /* if the literal value of the right hand side
     is greater than 4 then it is not worth it */
  if (icount > 4)
    return FALSE;

  /* if increment 16 bits in register */
  if (sameRegs (AOP (IC_LEFT (ic)), AOP (IC_RESULT (ic))) &&
      size > 1 &&
      icount == 1
    )
    {
      int offset = 0;
      symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
      while (size--)
        {
          emit3_o (A_INC, AOP (IC_RESULT (ic)), offset++, 0, 0);
          if (size)
            {
              if(!regalloc_dry_run)
                emit2 ("jp NZ,!tlabel", tlbl->key + 100);
              regalloc_dry_run_cost += 3;
            }
        }
      if (!regalloc_dry_run)
        AOP_TYPE (IC_LEFT (ic)) == AOP_HL ? emitLabel (tlbl->key + 100) : emitLabelNoSpill (tlbl->key + 100);
      else if (AOP_TYPE (IC_LEFT (ic)) == AOP_HL)
        spillCached ();
      return TRUE;
    }

  /* if the sizes are greater than 1 then we cannot */
  if (AOP_SIZE (IC_RESULT (ic)) > 1 ||
      AOP_SIZE (IC_LEFT (ic)) > 1)
    return FALSE;

  /* If the result is in a register then we can load then increment.
   */
  if (AOP_TYPE (IC_RESULT (ic)) == AOP_REG)
    {
      cheapMove (AOP (IC_RESULT (ic)), LSB, AOP (IC_LEFT (ic)), LSB);
      while (icount--)
          emit3_o (A_INC, AOP (IC_RESULT (ic)), LSB, 0, 0);
      return TRUE;
    }

  /* we can if the aops of the left & result match or
     if they are in registers and the registers are the
     same */
  if (sameRegs (AOP (IC_LEFT (ic)), AOP (IC_RESULT (ic))))
    {
      while (icount--)
        emit3 (A_INC, AOP (IC_LEFT (ic)), 0);
      return TRUE;
    }

  return FALSE;
}

/*-----------------------------------------------------------------*/
/* outBitAcc - output a bit in acc                                 */
/*-----------------------------------------------------------------*/
static void
outBitAcc (operand * result)
{
  symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
  /* if the result is a bit */
  if (AOP_TYPE (result) == AOP_CRY)
    {
      wassertl (0, "Tried to write A into a bit");
    }
  else
    {
      if(!regalloc_dry_run)
        {
          emit2 ("jp Z,!tlabel", tlbl->key + 100);
          emit2 ("ld a,!one");
          emitLabelNoSpill (tlbl->key + 100);
        }
      regalloc_dry_run_cost += 5;
      outAcc (result);
    }
}

static bool
couldDestroyCarry (asmop *aop)
{
  if (aop)
    {
      if (aop->type == AOP_EXSTK || aop->type == AOP_IY)
        {
          return TRUE;
        }
    }
  return FALSE;
}

static void
shiftIntoPair (int idx, asmop *aop)
{
  PAIR_ID id = PAIR_INVALID;

  wassertl (!IS_GB, "Not implemented for the GBZ80");
  //  wassertl (aop->type == AOP_EXSTK, "Only implemented for EXSTK");

  emitDebug ("; Shift into pair idx %u", idx);

  switch (idx)
    {
    case 0:
      id = PAIR_HL;
      setupPair (PAIR_HL, aop, 0);
      break;
    case 1:
      id = PAIR_DE;
      _push (PAIR_DE);
      setupPair (PAIR_IY, aop, 0);
      emit2 ("push iy");
      emit2 ("pop %s", _pairs[id].name);
      break;
    case 2:
      id = PAIR_IY;
      setupPair (PAIR_IY, aop, 0);
      break;
    default:
      wassertl (0, "Internal error - hit default case");
    }

  aop->type = AOP_PAIRPTR;
  aop->aopu.aop_pairId = id;
  _G.pairs[id].offset = 0;
  _G.pairs[id].last_type = aop->type;
}

static void
setupToPreserveCarry (const iCode *ic)
{
  asmop *left   = AOP (IC_LEFT (ic));
  asmop *right  = AOP (IC_RIGHT (ic));
  asmop *result = AOP (IC_RESULT (ic));

  wassert (left && right);

  if (!IS_GB)
    {
      if (couldDestroyCarry (right) && couldDestroyCarry (result))
        {
          shiftIntoPair (0, right);
          /* check result again, in case right == result */
          if (couldDestroyCarry (result))
            {
              if (!isPairInUse (PAIR_DE, ic))
                shiftIntoPair (1, result);
              else
                shiftIntoPair (2, result);
            }
        }
      else if (couldDestroyCarry (right))
        {
          if (getPairId (result) == PAIR_HL)
            _G.preserveCarry = TRUE;
          else
            shiftIntoPair (0, right);
        }
      else if (couldDestroyCarry (result))
        {
          shiftIntoPair (0, result);
        }
      else
        {
          /* Fine */
        }
    }
}

/*-----------------------------------------------------------------*/
/* genPlus - generates code for addition                           */
/*-----------------------------------------------------------------*/
static void
genPlus (iCode * ic)
{
  int size, offset = 0;
  bool premoved;

  /* special cases :- */

  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);
  aopOp (IC_RIGHT (ic), ic, FALSE, FALSE);
  aopOp (IC_RESULT (ic), ic, TRUE, FALSE);

  /* Swap the left and right operands if:

     if literal, literal on the right or
     if left requires ACC or right is already
     in ACC */
  if ((AOP_TYPE (IC_LEFT (ic)) == AOP_LIT) ||
      (AOP_NEEDSACC (IC_RIGHT (ic))) ||
      AOP_TYPE (IC_RIGHT (ic)) == AOP_ACC)
    {
      operand *t = IC_RIGHT (ic);
      IC_RIGHT (ic) = IC_LEFT (ic);
      IC_LEFT (ic) = t;
    }

  /* if both left & right are in bit
     space */
  if (AOP_TYPE (IC_LEFT (ic)) == AOP_CRY &&
      AOP_TYPE (IC_RIGHT (ic)) == AOP_CRY)
    {
      /* Cant happen */
      wassertl (0, "Tried to add two bits");
    }

  /* if left in bit space & right literal */
  if (AOP_TYPE (IC_LEFT (ic)) == AOP_CRY &&
      AOP_TYPE (IC_RIGHT (ic)) == AOP_LIT)
    {
      /* Can happen I guess */
      wassertl (0, "Tried to add a bit to a literal");
    }

  /* if I can do an increment instead
     of add then GOOD for ME */
  if (genPlusIncr (ic) == TRUE)
    goto release;

  size = getDataSize (IC_RESULT (ic));

  /* Special case when left and right are constant */
  if (isPair (AOP (IC_RESULT (ic))))
    {
      char *left = Safe_strdup (aopGetLitWordLong (AOP (IC_LEFT (ic)), 0, FALSE));
      const char *right = aopGetLitWordLong (AOP (IC_RIGHT (ic)), 0, FALSE);

      if (AOP_TYPE(IC_LEFT(ic)) == AOP_LIT && AOP_TYPE(IC_RIGHT(ic)) == AOP_LIT &&
          left && right)
        {
          struct dbuf_s dbuf;

          /* It's a pair */
          /* PENDING: fix */
          dbuf_init (&dbuf, 128);
          dbuf_printf (&dbuf, "#(%s + %s)", left, right);
          Safe_free (left);
          emit2 ("ld %s,%s", getPairName (AOP (IC_RESULT (ic))), dbuf_c_str (&dbuf));
          dbuf_destroy (&dbuf);
          regalloc_dry_run_cost += (getPairId (AOP (IC_RESULT (ic))) == PAIR_IY ? 4 : 3);
          goto release;
        }
      Safe_free (left);
    }

  if ((isPair (AOP (IC_RIGHT (ic))) || isPair (AOP (IC_LEFT (ic)))) && getPairId (AOP (IC_RESULT (ic))) == PAIR_HL)
    {
      /* Fetch into HL then do the add */
      PAIR_ID left = getPairId (AOP (IC_LEFT (ic)));
      PAIR_ID right = getPairId (AOP (IC_RIGHT (ic)));

      spillPair (PAIR_HL);

      if (left == PAIR_HL && right != PAIR_INVALID)
        {
          emit2 ("add hl,%s", _pairs[right].name);
          regalloc_dry_run_cost += 1;
          goto release;
        }
      else if (right == PAIR_HL && left != PAIR_INVALID)
        {
          emit2 ("add hl,%s", _pairs[left].name);
          regalloc_dry_run_cost += 1;
          goto release;
        }
      else if (right != PAIR_INVALID && right != PAIR_HL)
        {
          fetchPair (PAIR_HL, AOP (IC_LEFT (ic)));
          emit2 ("add hl,%s", getPairName (AOP (IC_RIGHT (ic))));
          regalloc_dry_run_cost += 1;
          goto release;
        }
      else if (left != PAIR_INVALID && left != PAIR_HL)
        {
          fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
          emit2 ("add hl,%s", getPairName (AOP (IC_LEFT (ic))));
          regalloc_dry_run_cost += 1;
          goto release;
        }
      else
        {
          /* Can't do it */
        }
    }

  if (getPairId (AOP (IC_RESULT (ic))) == PAIR_IY)
    {
      bool save_pair = FALSE;
      PAIR_ID pair;

      if (getPairId (AOP (IC_RIGHT (ic))) == PAIR_IY || getPairId (AOP (IC_LEFT (ic))) == PAIR_BC || getPairId (AOP (IC_LEFT (ic))) == PAIR_DE ||
        getPairId (AOP (IC_LEFT (ic))) != PAIR_IY && (AOP_TYPE (IC_RIGHT (ic)) == AOP_IMMD || AOP_TYPE (IC_RIGHT (ic)) == AOP_LIT || AOP_TYPE (IC_RIGHT (ic)) == AOP_SIMPLELIT))
        {
          operand *t = IC_RIGHT (ic);
          IC_RIGHT (ic) = IC_LEFT (ic);
          IC_LEFT (ic) = t;
        }
      pair = getPairId (AOP (IC_RIGHT (ic)));
      if (pair != PAIR_BC && pair != PAIR_DE)
        {
          pair = isPairDead (PAIR_DE, ic) ? PAIR_DE : PAIR_BC;
          if (!isPairDead (pair, ic))
            save_pair = TRUE;
        }
      fetchPair (PAIR_IY, AOP (IC_LEFT (ic)));
      if (save_pair)
        _push (pair);
      fetchPair (pair, AOP (IC_RIGHT (ic)));
      emit2 ("add iy, %s", _pairs[pair].name);
      regalloc_dry_run_cost += 2;
      if (save_pair)
        _pop (pair);
      goto release;
    }

  if (isPair (AOP (IC_RIGHT (ic))) && AOP_TYPE (IC_LEFT (ic)) == AOP_IMMD && getPairId (AOP (IC_RIGHT (ic))) != PAIR_HL)
    {
      fetchPair (PAIR_HL, AOP (IC_LEFT (ic)));
      emit2 ("add hl,%s", getPairName (AOP (IC_RIGHT (ic))));
      regalloc_dry_run_cost += 1;
      spillPair (PAIR_HL);
      commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
      goto release;
    }

  if (isPair (AOP (IC_LEFT (ic))) && AOP_TYPE (IC_RIGHT (ic)) == AOP_LIT && getPairId (AOP (IC_LEFT (ic))) != PAIR_HL)
    {
      fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
      emit2 ("add hl,%s", getPairName (AOP (IC_LEFT (ic))));
      regalloc_dry_run_cost += 1;
      spillPair (PAIR_HL);
      commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
      goto release;
    }

  if (isPair (AOP (IC_LEFT (ic))) && isPair (AOP (IC_RIGHT (ic))) && getPairId (AOP (IC_LEFT (ic))) == PAIR_HL)
    {
      emit2 ("add hl,%s", getPairName (AOP (IC_RIGHT (ic))));
      regalloc_dry_run_cost += 1;
      spillPair (PAIR_HL);
      commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
      goto release;
    }

  if (isPair (AOP (IC_LEFT (ic))) && isPair (AOP (IC_RIGHT (ic))) && getPairId (AOP (IC_RIGHT (ic))) == PAIR_HL)
    {
      emit2 ("add hl,%s", getPairName (AOP (IC_LEFT (ic))));
      regalloc_dry_run_cost += 1;
      spillPair (PAIR_HL);
      commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
      goto release;
    }

  if (getPairId (AOP (IC_RESULT (ic))) == PAIR_HL && AOP_TYPE (IC_RIGHT (ic)) == AOP_REG &&
    AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == C_IDX && !bitVectBitValue(ic->rSurv, B_IDX))
    {
      if (AOP (IC_RIGHT (ic))->aopu.aop_reg[1] && (AOP (IC_RIGHT (ic))->aopu.aop_reg[1]->rIdx == H_IDX || AOP (IC_RIGHT (ic))->aopu.aop_reg[1]->rIdx == L_IDX))
        {
          cheapMove (ASMOP_B, 0, AOP (IC_RIGHT (ic)), 1);
          fetchPair (PAIR_HL, AOP (IC_LEFT (ic)));
        }
      else
        {
          fetchPair (PAIR_HL, AOP (IC_LEFT (ic)));
          cheapMove (ASMOP_B, 0, AOP (IC_RIGHT (ic)), 1);
        }
      emit2 ("add hl, bc");
      regalloc_dry_run_cost += 1;
      goto release;
    }
  if (!z80_opts.oldralloc && getPairId (AOP (IC_RESULT (ic))) == PAIR_HL && AOP_TYPE (IC_LEFT (ic)) == AOP_REG &&
    AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == C_IDX && !bitVectBitValue(ic->rSurv, B_IDX))
    {
      if (AOP (IC_LEFT (ic))->aopu.aop_reg[1] && (AOP (IC_LEFT (ic))->aopu.aop_reg[1]->rIdx == H_IDX || AOP (IC_LEFT (ic))->aopu.aop_reg[1]->rIdx == L_IDX))
        {
          cheapMove (ASMOP_B, 0, AOP (IC_LEFT (ic)), 1);
          fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
        }
      else
        {
          fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
          cheapMove (ASMOP_B, 0, AOP (IC_LEFT (ic)), 1);
        }
      emit2 ("add hl, bc");
      regalloc_dry_run_cost += 1;
      goto release;
    }

  if (!z80_opts.oldralloc && getPairId (AOP (IC_RESULT (ic))) == PAIR_HL && AOP_TYPE (IC_RIGHT (ic)) == AOP_REG &&
    AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == E_IDX && !bitVectBitValue(ic->rSurv, D_IDX))
    {
      if (AOP (IC_RIGHT (ic))->aopu.aop_reg[1] && (AOP (IC_RIGHT (ic))->aopu.aop_reg[1]->rIdx == H_IDX || AOP (IC_RIGHT (ic))->aopu.aop_reg[1]->rIdx == L_IDX))
        {
          cheapMove (ASMOP_D, 0, AOP (IC_RIGHT (ic)), 1);
          fetchPair (PAIR_HL, AOP (IC_LEFT (ic)));
        }
      else
        {
          fetchPair (PAIR_HL, AOP (IC_LEFT (ic)));
          cheapMove (ASMOP_D, 0, AOP (IC_RIGHT (ic)), 1);
        }
      emit2 ("add hl, de");
      regalloc_dry_run_cost += 1;
      goto release;
    }
  if (!z80_opts.oldralloc && getPairId (AOP (IC_RESULT (ic))) == PAIR_HL && AOP_TYPE (IC_LEFT (ic)) == AOP_REG &&
    AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == E_IDX && !bitVectBitValue(ic->rSurv, D_IDX))
    {
      if (AOP (IC_LEFT (ic))->aopu.aop_reg[1] && (AOP (IC_LEFT (ic))->aopu.aop_reg[1]->rIdx == H_IDX || AOP (IC_LEFT (ic))->aopu.aop_reg[1]->rIdx == L_IDX))
        {
          cheapMove (ASMOP_D, 0, AOP (IC_LEFT (ic)), 1);
          fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
        }
      else
        {
          fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
          cheapMove (ASMOP_D, 0, AOP (IC_LEFT (ic)), 1);
        }
      emit2 ("add hl, de");
      regalloc_dry_run_cost += 1;
      goto release;
    }
    
  /* Special case:
     ld hl,sp+n trashes C so we can't afford to do it during an
     add with stack based variables.  Worst case is:
     ld  hl,sp+left
     ld  a,(hl)
     ld  hl,sp+right
     add (hl)
     ld  hl,sp+result
     ld  (hl),a
     ld  hl,sp+left+1
     ld  a,(hl)
     ld  hl,sp+right+1
     adc (hl)
     ld  hl,sp+result+1
     ld  (hl),a
     So you can't afford to load up hl if either left, right, or result
     is on the stack (*sigh*)  The alt is:
     ld  hl,sp+left
     ld  de,(hl)
     ld  hl,sp+right
     ld  hl,(hl)
     add hl,de
     ld  hl,sp+result
     ld  (hl),hl
     Combinations in here are:
     * If left or right are in bc then the loss is small - trap later
     * If the result is in bc then the loss is also small
   */
  if (IS_GB)
    {
      if (AOP_TYPE (IC_LEFT (ic)) == AOP_STK ||
          AOP_TYPE (IC_RIGHT (ic)) == AOP_STK ||
          AOP_TYPE (IC_RESULT (ic)) == AOP_STK)
        {
          if ((AOP_SIZE (IC_LEFT (ic)) == 2 ||
               AOP_SIZE (IC_RIGHT (ic)) == 2) &&
              (AOP_SIZE (IC_LEFT (ic)) <= 2 &&
               AOP_SIZE (IC_RIGHT (ic)) <= 2))
            {
              if (getPairId (AOP (IC_RIGHT (ic))) == PAIR_BC)
                {
                  /* Swap left and right */
                  operand *t = IC_RIGHT (ic);
                  IC_RIGHT (ic) = IC_LEFT (ic);
                  IC_LEFT (ic) = t;
                }
              if (getPairId (AOP (IC_LEFT (ic))) == PAIR_BC)
                {
                  fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
                  emit2 ("add hl,bc");
                  regalloc_dry_run_cost += 1;
                }
              else
                {
                  fetchPair (PAIR_DE, AOP (IC_LEFT (ic)));
                  fetchPair (PAIR_HL, AOP (IC_RIGHT (ic)));
                  emit2 ("add hl,de");
                  regalloc_dry_run_cost += 1;
                }
              commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
              goto release;
            }
        }
      if (size == 4)
        {
          /* Be paranoid on the GB with 4 byte variables due to how C
             can be trashed by lda hl,n(sp).
          */
          _gbz80_emitAddSubLong (ic, TRUE);
          goto release;
        }
    }
  
  // Avoid overwriting operand in h or l when setupToPreserveCarry () loads hl.
  if(!couldDestroyCarry (AOP (IC_LEFT (ic))))
    {
      cheapMove (ASMOP_A, 0, AOP (IC_LEFT (ic)), offset);
      premoved = TRUE;
    }
  else
    premoved = FALSE;
    
  setupToPreserveCarry (ic);

  while (size--)
    {
      if(!premoved)
        cheapMove (ASMOP_A, 0, AOP (IC_LEFT (ic)), offset);
      else
        premoved = FALSE;
      if (offset == 0)
      {
        if(size == 0 && AOP_TYPE (IC_RIGHT (ic)) == AOP_LIT && ulFromVal (AOP (IC_RIGHT (ic))->aopu.aop_lit) == 1)
          emit3 (A_INC, ASMOP_A, 0);
        else
          emit3_o (A_ADD, ASMOP_A, 0, AOP (IC_RIGHT (ic)), offset);
      }
      else
        emit3_o (A_ADC, ASMOP_A, 0, AOP (IC_RIGHT (ic)), offset);
      cheapMove (AOP (IC_RESULT (ic)), offset++, ASMOP_A, 0);
    }
release:
  _G.preserveCarry = FALSE;
  freeAsmop (IC_LEFT (ic), NULL, ic);
  freeAsmop (IC_RIGHT (ic), NULL, ic);
  freeAsmop (IC_RESULT (ic), NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genMinusDec :- does subtraction with deccrement if possible     */
/*-----------------------------------------------------------------*/
static bool
genMinusDec (const iCode * ic)
{
  unsigned int icount;
  unsigned int size = getDataSize (IC_RESULT (ic));

  /* will try to generate an increment */
  /* if the right side is not a literal we cannot */
  if (AOP_TYPE (IC_RIGHT (ic)) != AOP_LIT)
    return FALSE;

  /* if the literal value of the right hand side
     is greater than 4 then it is not worth it */
  if ((icount = (unsigned int) ulFromVal (AOP (IC_RIGHT (ic))->aopu.aop_lit)) > 2)
    return FALSE;

  size = getDataSize (IC_RESULT (ic));

  /* if decrement 16 bits in register */
  if (sameRegs (AOP (IC_LEFT (ic)), AOP (IC_RESULT (ic))) &&
      (size > 1) && isPair (AOP (IC_RESULT (ic))))
    {
      while (icount--)
        emit2 ("dec %s", getPairName (AOP (IC_RESULT (ic))));
      return TRUE;
    }

  /* If result is a pair */
  if (isPair (AOP (IC_RESULT (ic))))
    {
      movLeft2ResultLong (IC_LEFT (ic), 0, IC_RESULT (ic), 0, 0, 2);
      while (icount--)
        if (!regalloc_dry_run)
          emit2 ("dec %s", getPairName (AOP (IC_RESULT (ic))));
        regalloc_dry_run_cost += 1;
      return TRUE;
    }

  /* if increment 16 bits in register */
  if (sameRegs (AOP (IC_LEFT (ic)), AOP (IC_RESULT (ic))) &&
      (size == 2)
      )
    {
      fetchPair (_getTempPairId(), AOP (IC_RESULT (ic)));

      while (icount--)
        if (!regalloc_dry_run)
          emit2 ("dec %s", _getTempPairName());
        regalloc_dry_run_cost += 1;

      commitPair (AOP (IC_RESULT (ic)), _getTempPairId());

      return TRUE;
    }


  /* if the sizes are greater than 1 then we cannot */
  if (AOP_SIZE (IC_RESULT (ic)) > 1 ||
      AOP_SIZE (IC_LEFT (ic)) > 1)
    return FALSE;

  /* we can if the aops of the left & result match or if they are in
     registers and the registers are the same */
  if (sameRegs (AOP (IC_LEFT (ic)), AOP (IC_RESULT (ic))))
    {
      while (icount--)
        emit3 (A_DEC, AOP (IC_RESULT (ic)), 0);
      return TRUE;
    }

  return FALSE;
}

/*-----------------------------------------------------------------*/
/* genMinus - generates code for subtraction                       */
/*-----------------------------------------------------------------*/
static void
genMinus (const iCode * ic)
{
  int size, offset = 0;
  unsigned long lit = 0L;

  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);
  aopOp (IC_RIGHT (ic), ic, FALSE, FALSE);
  aopOp (IC_RESULT (ic), ic, TRUE, FALSE);

  /* special cases :- */
  /* if both left & right are in bit space */
  if (AOP_TYPE (IC_LEFT (ic)) == AOP_CRY &&
      AOP_TYPE (IC_RIGHT (ic)) == AOP_CRY)
    {
      wassertl (0, "Tried to subtract two bits");
      goto release;
    }

  /* if I can do an decrement instead of subtract then GOOD for ME */
  if (genMinusDec (ic) == TRUE)
    goto release;

  size = getDataSize (IC_RESULT (ic));

  if (AOP_TYPE (IC_RIGHT (ic)) != AOP_LIT)
    {
    }
  else
    {
      lit = ulFromVal (AOP (IC_RIGHT (ic))->aopu.aop_lit);
      lit = -(long) lit;
    }

  /* Same logic as genPlus */
  if (IS_GB)
    {
      if (AOP_TYPE (IC_LEFT (ic)) == AOP_STK ||
          AOP_TYPE (IC_RIGHT (ic)) == AOP_STK ||
          AOP_TYPE (IC_RESULT (ic)) == AOP_STK)
        {
          if ((AOP_SIZE (IC_LEFT (ic)) == 2 ||
               AOP_SIZE (IC_RIGHT (ic)) == 2) &&
              (AOP_SIZE (IC_LEFT (ic)) <= 2 &&
               AOP_SIZE (IC_RIGHT (ic)) <= 2))
            {
              PAIR_ID left = getPairId (AOP (IC_LEFT (ic)));
              PAIR_ID right = getPairId (AOP (IC_RIGHT (ic)));

              if (left == PAIR_INVALID && right == PAIR_INVALID)
                {
                  left = PAIR_DE;
                  right = PAIR_HL;
                }
              else if (right == PAIR_INVALID)
                right = PAIR_DE;
              else if (left == PAIR_INVALID)
                left = PAIR_DE;

              fetchPair (left, AOP (IC_LEFT (ic)));
              /* Order is important.  Right may be HL */
              fetchPair (right, AOP (IC_RIGHT (ic)));

              if(!regalloc_dry_run)
                {
                  emit2 ("ld a,%s", _pairs[left].l);
                  emit2 ("sub a,%s", _pairs[right].l);
                  emit2 ("ld e,a");
                  emit2 ("ld a,%s", _pairs[left].h);
                  emit2 ("sbc a,%s", _pairs[right].h);
                }
              regalloc_dry_run_cost += 5;

              if ( AOP_SIZE (IC_RESULT (ic)) > 1)
                cheapMove (AOP (IC_RESULT (ic)), 1, ASMOP_A, 0);
              aopPut (AOP (IC_RESULT (ic)), "e", 0);
              goto release;
            }
        }
      if (size == 4)
        {
          /* Be paranoid on the GB with 4 byte variables due to how C
             can be trashed by lda hl,n(sp).
          */
          _gbz80_emitAddSubLong (ic, FALSE);
          goto release;
        }
    }

  setupToPreserveCarry (ic);

  /* if literal, add a,#-lit, else normal subb */
  while (size--)
    {
      cheapMove (ASMOP_A, 0, AOP (IC_LEFT (ic)), offset);
      if (AOP_TYPE (IC_RIGHT (ic)) != AOP_LIT)
        {
          if (!offset)
            emit3_o (A_SUB, ASMOP_A, 0, AOP (IC_RIGHT (ic)), offset);
          else
            emit3_o (A_SBC, ASMOP_A, 0, AOP (IC_RIGHT (ic)), offset);
        }
      else
        {
          /* first add without previous c */
          if (!offset)
            {
              if (size == 0 && (unsigned int) (lit & 0x0FFL) == 0xFF)
                emit3 (A_DEC, ASMOP_A, 0);
              else
                {
                  if(!regalloc_dry_run)
                    emit2 ("add a,!immedbyte", (unsigned int) (lit & 0x0FFL));
                  regalloc_dry_run_cost += 2;
                }
            }
          else
            emit2 ("adc a,!immedbyte", (unsigned int) ((lit >> (offset * 8)) & 0x0FFL));
        }
      cheapMove (AOP (IC_RESULT (ic)), offset++, ASMOP_A, 0);
    }

  if (AOP_SIZE (IC_RESULT (ic)) == 3 &&
      AOP_SIZE (IC_LEFT (ic)) == 3 &&
      !sameRegs (AOP (IC_RESULT (ic)), AOP (IC_LEFT (ic))))
    {
      wassertl (0, "Tried to subtract on a long pointer");
    }

release:
  _G.preserveCarry = FALSE;
  freeAsmop (IC_LEFT (ic), NULL, ic);
  freeAsmop (IC_RIGHT (ic), NULL, ic);
  freeAsmop (IC_RESULT (ic), NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genMultOneChar - generates code for unsigned 8x8 multiplication */
/*-----------------------------------------------------------------*/
static void
genMultOneChar (const iCode * ic)
{
  symbol *tlbl1, *tlbl2;
  bool savedB = FALSE;

  asmop *result = AOP (IC_RESULT (ic));
  int resultsize = AOP_SIZE (IC_RESULT (ic));

  if(IS_GB)
    {
      wassertl (0, "Multiplication is handled through support function calls on gbz80");
      return;
    }

  if (IS_Z180 &&
    /*AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP_TYPE (IC_RIGHT (ic)) == AOP_REG &&*/ AOP_TYPE (IC_RESULT (ic)) == AOP_REG)
    {
      if (/*(AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == B_IDX && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == C_IDX ||
        AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == C_IDX && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == B_IDX) &&*/
        (resultsize > 1 ? result->aopu.aop_reg[1]->rIdx == B_IDX : !bitVectBitValue (ic->rSurv, B_IDX)) && result->aopu.aop_reg[0]->rIdx == C_IDX)
        {
          if(AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == C_IDX ||
            AOP_TYPE (IC_RIGHT (ic)) == AOP_REG && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == B_IDX)
            {
              cheapMove(ASMOP_C, 0, AOP (IC_LEFT (ic)), LSB);
              cheapMove(ASMOP_B, 0, AOP (IC_RIGHT (ic)), LSB);
            }
          else
            {
              cheapMove(ASMOP_B, 0, AOP (IC_LEFT (ic)), LSB);
              cheapMove(ASMOP_C, 0, AOP (IC_RIGHT (ic)), LSB);
            }
          emit2 ("mlt bc");
          regalloc_dry_run_cost += 2;
          return;
        }
      if (/*(AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == D_IDX && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == E_IDX ||
        AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == E_IDX && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == D_IDX) &&*/
        (resultsize > 1 ? result->aopu.aop_reg[1]->rIdx == D_IDX : !bitVectBitValue (ic->rSurv, D_IDX)) && result->aopu.aop_reg[0]->rIdx == E_IDX)
        {
          if(AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == E_IDX ||
            AOP_TYPE (IC_RIGHT (ic)) == AOP_REG && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == D_IDX)
            {
              cheapMove(ASMOP_E, 0, AOP (IC_LEFT (ic)), LSB);
              cheapMove(ASMOP_D, 0, AOP (IC_RIGHT (ic)), LSB);
            }
          else
            {
              cheapMove(ASMOP_D, 0, AOP (IC_LEFT (ic)), LSB);
              cheapMove(ASMOP_E, 0, AOP (IC_RIGHT (ic)), LSB);
            }
          emit2 ("mlt de");
          regalloc_dry_run_cost += 2;
          return;
        }
      if (AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP_TYPE (IC_RIGHT (ic)) == AOP_REG &&
        ((AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == H_IDX && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == L_IDX ||
        AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == L_IDX && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == H_IDX) &&
        (resultsize > 1 ? result->aopu.aop_reg[1]->rIdx == H_IDX : !bitVectBitValue (ic->rSurv, H_IDX)) && result->aopu.aop_reg[0]->rIdx == L_IDX))
        {
          emit2 ("mlt hl");
          regalloc_dry_run_cost += 2;
          return;
        }
    }

  if (!isPairDead (PAIR_DE, ic))
    {
      _push (PAIR_DE);
      _G.stack.pushedDE = TRUE;
    }
  if (IS_R2K && !isPairDead (PAIR_BC, ic) ||
    !IS_Z180 && (!z80_opts.oldralloc && bitVectBitValue (ic->rSurv, B_IDX) ||
    z80_opts.oldralloc && bitVectBitValue (ic->rMask, B_IDX) && !(getPairId (AOP (IC_RESULT (ic))) == PAIR_BC)))
    {
      _push (PAIR_BC);
      savedB = TRUE;
    }

  // genMult() already swapped operands if necessary.
  if (AOP_TYPE (IC_LEFT (ic)) == AOP_REG && AOP (IC_LEFT (ic))->aopu.aop_reg[0]->rIdx == E_IDX ||
    AOP_TYPE (IC_RIGHT (ic)) == AOP_REG && AOP (IC_RIGHT (ic))->aopu.aop_reg[0]->rIdx == H_IDX && !requiresHL (AOP (IC_LEFT (ic))))
    {
      cheapMove (ASMOP_E, 0, AOP (IC_LEFT (ic)), LSB);
      cheapMove (ASMOP_H, 0, AOP (IC_RIGHT (ic)), LSB);
    }
  else
    {
      cheapMove (ASMOP_E, 0, AOP (IC_RIGHT (ic)), LSB);
      cheapMove (ASMOP_H, 0, AOP (IC_LEFT (ic)), LSB);
    }

  if (IS_Z180)
    {
      emit2 ("ld l, e");
      emit2 ("mlt hl");
      regalloc_dry_run_cost += 3;
    }
  else if(IS_R2K)
    {
      emit2 ("ld c, h");
      emit2 ("ld d, #0x00");
      emit2 ("ld b, d");
      emit2 ("mul");
      emit2 ("ld l, c");
      emit2 ("ld h, b");
      regalloc_dry_run_cost += 7;
    }
  else if (!regalloc_dry_run)
    {
      tlbl1 = newiTempLabel (NULL);
      tlbl2 = newiTempLabel (NULL);
      emit2 ("ld l,#0x00");
      emit2 ("ld d,l");
      emit2 ("ld b,#0x08");
      emitLabelNoSpill (tlbl1->key + 100);
      emit2 ("add hl,hl");
      emit2 ("jp NC,!tlabel", tlbl2->key + 100);
      emit2 ("add hl,de");
      emitLabelNoSpill (tlbl2->key + 100);
      emit2 ("djnz !tlabel", tlbl1->key + 100);
      regalloc_dry_run_cost += 12;
    }
  else
    regalloc_dry_run_cost += 12;


  spillPair(PAIR_HL);

  if (savedB)
    {
      _pop (PAIR_BC);
    }
  if (_G.stack.pushedDE)
    {
      _pop (PAIR_DE);
      _G.stack.pushedDE = FALSE;
    }

  if(result->type != AOP_HL)
    {
    if (resultsize == 1)
      cheapMove (result, 0, ASMOP_L, 0);
    else
      commitPair (result, PAIR_HL);
    }
  else
    {
    if (resultsize == 1)
      {
        emit2("ld a, l");
        regalloc_dry_run_cost += 1;
        cheapMove (result, 0, ASMOP_A, 0);
      }
    else
      {
        if(!isPairDead (PAIR_DE, ic))
          {
            _push (PAIR_DE);
            _G.stack.pushedDE = TRUE;
          }
        emit2("ld e, l");
        emit2("ld d, h");
        regalloc_dry_run_cost += 2;
        commitPair (result, PAIR_DE);
        if(!isPairDead (PAIR_DE, ic))
          {
            _pop (PAIR_DE);
            _G.stack.pushedDE = FALSE;
          }
      }
    }
}

/*-----------------------------------------------------------------*/
/* genMult - generates code for multiplication                     */
/*-----------------------------------------------------------------*/
static void
genMult (iCode *ic)
{
  int val;
  int count, i;
  /* If true then the final operation should be a subtract */
  bool active = FALSE;
  bool byteResult;

  /* Shouldn't occur - all done through function calls */
  aopOp (IC_LEFT (ic), ic, FALSE, FALSE);
  aopOp (IC_RIGHT (ic), ic, FALSE, FALSE);
  aopOp (IC_RESULT (ic), ic, TRUE, FALSE);

  byteResult =  (AOP_SIZE (IC_RESULT (ic)) == 1);

  if (AOP_SIZE (IC_LEFT (ic)) > 2 ||
      AOP_SIZE (IC_RIGHT (ic)) > 2 ||
      AOP_SIZE (IC_RESULT (ic)) > 2)
    {
      wassertl (0, "Multiplication is handled through support function calls.");
    }

  /* Swap left and right such that right is a literal */
  if (AOP_TYPE (IC_LEFT (ic)) == AOP_LIT)
    {
      operand *t = IC_RIGHT (ic);
      IC_RIGHT (ic) = IC_LEFT (ic);
      IC_LEFT (ic) = t;
    }

  if (AOP_TYPE (IC_RIGHT (ic)) != AOP_LIT)
    {
      genMultOneChar (ic);
      goto release;
    }

  wassertl (AOP_TYPE (IC_RIGHT (ic)) == AOP_LIT, "Right must be a literal.");

  val = (int) ulFromVal ( AOP (IC_RIGHT (ic))->aopu.aop_lit);
  //  wassertl (val > 0, "Multiply must be positive");
  wassertl (val != 1, "Can't multiply by 1");

  if (!IS_GB && (byteResult ? bitVectBitValue (ic->rSurv, E_IDX) : !isPairDead (PAIR_DE, ic))) {
    _push (PAIR_DE);
    _G.stack.pushedDE = TRUE;
  }

  if (byteResult)
    cheapMove (ASMOP_A, 0, AOP (IC_LEFT (ic)), LSB);
  else if ( AOP_SIZE (IC_LEFT (ic)) == 1 && !SPEC_USIGN (getSpec (operandType ( IC_LEFT (ic)))))
    {
      cheapMove (ASMOP_E, 0, AOP (IC_LEFT (ic)), LSB);
      if (!byteResult)
        {
          emit2 ("ld a,e");
          emit2 ("rlc a");
          emit2 ("sbc a,a");
          emit2 ("ld d,a");
          regalloc_dry_run_cost += 5;
        }
    }
  else
    fetchPair (PAIR_DE, AOP (IC_LEFT (ic)));

  i = val;

  for (count = 0; count < 16; count++)
    {
      if (count != 0 && active)
        {
          if (byteResult)
            emit2 ("add a,a");
          else
            emit2 ("add hl,hl");
          regalloc_dry_run_cost += 1;
        }
      if (i & 0x8000U)
        {
          if (active == FALSE)
            {
              if (byteResult)
                emit3 (A_LD, ASMOP_E, ASMOP_A);
              else
                {
                  emit2 ("ld l,e");
                  emit2 ("ld h,d");
                  regalloc_dry_run_cost += 2;
                }
            }
          else
            {
              if (byteResult)
                emit2 ("add a,e");
              else
                emit2 ("add hl,de");
              regalloc_dry_run_cost += 1;
            }
          active = TRUE;
        }
      i <<= 1;
    }

  spillPair(PAIR_HL);

  if (!IS_GB && _G.stack.pushedDE)
    {
      _pop (PAIR_DE);
      _G.stack.pushedDE = FALSE;
    }

  if (byteResult)
    cheapMove (AOP (IC_RESULT (ic)), 0, ASMOP_A, 0);
  else
    commitPair ( AOP (IC_RESULT (ic)), PAIR_HL);

release:
  freeAsmop (IC_LEFT (ic), NULL, ic);
  freeAsmop (IC_RIGHT (ic), NULL, ic);
  freeAsmop (IC_RESULT (ic), NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genDiv - generates code for division                            */
/*-----------------------------------------------------------------*/
static void
genDiv (const iCode *ic)
{
  /* Shouldn't occur - all done through function calls */
  wassertl (0, "Division is handled through support function calls");
}

/*-----------------------------------------------------------------*/
/* genMod - generates code for division                            */
/*-----------------------------------------------------------------*/
static void
genMod (const iCode *ic)
{
  /* Shouldn't occur - all done through function calls */
  wassert (0);
}

/*-----------------------------------------------------------------*/
/* genIfxJump :- will create a jump depending on the ifx           */
/*-----------------------------------------------------------------*/
static void
genIfxJump (iCode *ic, char *jval)
{
  symbol *jlbl;
  const char *inst;

  /* if true label then we jump if condition
     supplied is true */
  if (IC_TRUE (ic))
    {
      jlbl = IC_TRUE (ic);
      if (!strcmp (jval, "a"))
        {
          emit3 (A_OR, ASMOP_A, ASMOP_A);
          inst = "NZ";
        }
      else if (!strcmp (jval, "c"))
        {
          inst = "C";
        }
      else if (!strcmp (jval, "nc"))
        {
          inst = "NC";
        }
      else if (!strcmp (jval, "m"))
        {
          inst = "M";
        }
      else if (!strcmp (jval, "p"))
        {
          inst = "P";
        }
      else if (!strcmp (jval, "po"))
        {
          inst = "PO";
        }
      else if (!strcmp (jval, "pe"))
        {
          inst = "PE";
        }
      else
        {
          /* The buffer contains the bit on A that we should test */
          emit2 ("bit %s,a", jval);
          regalloc_dry_run_cost += 2;
          inst = "NZ";
        }
    }
  else
    {
      /* false label is present */
      jlbl = IC_FALSE (ic);
      if (!strcmp (jval, "a"))
        {
          emit3 (A_OR, ASMOP_A, ASMOP_A);
          inst = "Z";
        }
      else if (!strcmp (jval, "c"))
        {
          inst = "NC";
        }
      else if (!strcmp (jval, "nc"))
        {
          inst = "C";
        }
      else if (!strcmp (jval, "m"))
        {
          inst = "P";
        }
      else if (!strcmp (jval, "p"))
        {
          inst = "M";
        }
      else if (!strcmp (jval, "po"))
        {
          inst = "PE";
        }
      else if (!strcmp (jval, "pe"))
        {
          inst = "PO";
        }
      else
        {
          /* The buffer contains the bit on A that we should test */
          emit2 ("bit %s,a", jval);
          regalloc_dry_run_cost += 2;
          inst = "Z";
        }
    }
  /* Z80 can do a conditional long jump */
  if(!regalloc_dry_run)
    emit2 ("jp %s,!tlabel", inst, jlbl->key + 100);
  regalloc_dry_run_cost += 3;

  /* mark the icode as generated */
  if(!regalloc_dry_run)
    ic->generated = 1;
}

#if DISABLED
static const char *
_getPairIdName (PAIR_ID id)
{
  return _pairs[id].name;
}
#endif

/** Generic compare for > or <
 */
static void
genCmp (operand * left, operand * right,
        operand * result, iCode * ifx, int sign)
{
  int size, offset = 0;
  unsigned long lit = 0L;
  bool result_in_carry = FALSE;

  /* if left & right are bit variables */
  if (AOP_TYPE (left) == AOP_CRY &&
      AOP_TYPE (right) == AOP_CRY)
    {
      /* Can't happen on the Z80 */
      wassertl (0, "Tried to compare two bits");
    }
  else
    {
      /* Do a long subtract of right from left. */
      size = max (AOP_SIZE (left), AOP_SIZE (right));

      // On the Gameboy we can't afford to adjust HL as it may trash the carry.
      if (size > 1 && IS_GB && (requiresHL(AOP(right)) && requiresHL(AOP(left))))
        {
          // Pull left into DE and right into HL
          aopGet (AOP(left), LSB, FALSE);
          emit2 ("ld d, h");
          emit2 ("ld e, l");
          aopGet (AOP(right), LSB, FALSE);

          while (size--)
            {
              emit2 ("ld a, (de)");
              emit2 ("%s a, (hl)", offset == 0 ? "sub" : "sbc");

              if (size != 0)
                {
                  emit2 ("inc hl");
                  emit2 ("inc de");
                }
              offset++;
            }
          if(sign)
            {
              emit2("ld a, (de)");
              emit2("ld d, a");
              emit2("ld e, (hl)");
            }
          spillPair (PAIR_HL);
          result_in_carry = TRUE;
          goto fix;
        }
      else if (size > 1 && IS_GB && (requiresHL(AOP(right)) && !requiresHL(AOP(left))))
        {
          aopGet (AOP(right), LSB, FALSE);

          while (size--)
            {
              emit2 ("ld a, %s", aopGet (AOP (left), offset, FALSE));
              emit2 ("%s a, (hl)", offset == 0 ? "sub" : "sbc");

              if (size != 0)
                {
                  emit2 ("inc hl");
                }
              offset++;
            }
          if(sign)
            {
              emit2("ld a, %s", aopGet (AOP (left), offset, FALSE));
              emit2("ld d, a");
              emit2("ld e, (hl)");
            }
          spillPair (PAIR_HL);
          result_in_carry = TRUE;
          goto fix;
        }
      else if (size > 1 && IS_GB && (!requiresHL(AOP(right)) && requiresHL(AOP(left))))
        {
          aopGet (AOP(left), LSB, FALSE);

          while (size--)
            {
              emit2 ("ld a, (hl)");
              emit2 ("%s a, %s", offset == 0 ? "sub" : "sbc", aopGet (AOP (right), offset, FALSE));

              if (size != 0)
                {
                  emit2 ("inc hl");
                }
              offset++;
            }
          if(sign)
            {  
              emit2("ld d, (hl)");
              emit2("ld a, %s", aopGet (AOP (right), offset, FALSE));
              emit2("ld e, a");
            }
          spillPair (PAIR_HL);
          result_in_carry = TRUE;
          goto fix;
        }

      if(IS_GB && sign)
        {
          emit2 ("ld a, %s", aopGet (AOP (right), size - 1, FALSE));
          emit2 ("ld e, a");
          emit2 ("ld a, %s", aopGet (AOP (left), size - 1, FALSE));
          emit2 ("ld d, a");
        }

      if (AOP_TYPE (right) == AOP_LIT)
        {
          lit = ulFromVal (AOP (right)->aopu.aop_lit);
          /* optimize if(x < 0) or if(x >= 0) */
          if (lit == 0)
            {
              if (!sign)
                {
                  /* No sign so it's always false */
                  _clearCarry();
                  result_in_carry = TRUE;
                }
              else
                {
                  /* Just load in the top most bit */
                  cheapMove (ASMOP_A, 0, AOP (left), AOP_SIZE (left) - 1);
                  if (!(AOP_TYPE (result) == AOP_CRY && AOP_SIZE (result)) && ifx)
                    {
                      genIfxJump (ifx, "7");
                      return;
                    }
                  else
                    {
                      if (ifx)
                        {
                          genIfxJump (ifx, "nc");
                          return;
                        }
                      result_in_carry = FALSE;
                    }
                }
              goto release;
            }
          else
            while (!((lit >> (offset * 8)) & 0xff))
              {
                size--;
                offset++;
              }
        }

      cheapMove (ASMOP_A, 0, AOP (left), offset);
      emit3_o (A_SUB, ASMOP_A, 0, AOP (right), offset);
      size--;
      offset++;

      while (size--)
        {
          cheapMove (ASMOP_A, 0, AOP (left), offset);
          /* Subtract through, propagating the carry */
          emit3_o (A_SBC, ASMOP_A, 0, AOP (right), offset++);
        }

fix:
      /* There is no good signed compare in the Z80, so we need workarounds */
      if (sign)
        {
          if (!IS_GB) /* Directly check for overflow, can't be done on GBZ80 */
            {
              symbol *tlbl;
              if (!regalloc_dry_run)
                {
                  tlbl = newiTempLabel (NULL);
                  emit2 ("jp PO, !tlabel", tlbl->key + 100);
                  emit2 ("xor a, !immedbyte", 0x80);
                }
              regalloc_dry_run_cost += 5;
              if (!regalloc_dry_run)
                emitLabel (tlbl->key + 100);
              result_in_carry = FALSE;
            }
          else /* Do it the hard way */
            {
              /* Test if one operand is negative, while the other is not. If this is the
                 case we can easily decide which one is greater, and we set/reset the carry
                 flag. If not, then the unsigned compare gave the correct result and we
                 don't change the carry flag. */
              symbol *tlbl1 = newiTempLabel (NULL);
              symbol *tlbl2 = newiTempLabel (NULL);
              emit2 ("bit 7, e");
              emit2 ("jp Z, !tlabel", tlbl1->key + 100);
              emit2 ("bit 7, d");
              emit2 ("jp NZ, !tlabel", tlbl2->key + 100);
              emit2 ("cp a, a");
              emit2 ("jp !tlabel", tlbl2->key + 100);
              emitLabel (tlbl1->key + 100);
              emit2 ("bit 7, d");
              emit2 ("jp Z, !tlabel", tlbl2->key + 100);
              emit2 ("scf");
              emitLabel (tlbl2->key + 100);
              result_in_carry = TRUE;
            }
        }
      else
        result_in_carry = TRUE;
    }

release:
  if (AOP_TYPE (result) == AOP_CRY && AOP_SIZE (result))
    {
      if (!result_in_carry)
        {
          /* Shift the sign bit up into carry */
          emit2 ("rlca");
          regalloc_dry_run_cost += 1;
        }
      outBitC (result);
    }
  else
    {
      /* if the result is used in the next
         ifx conditional branch then generate
         code a little differently */
      if (ifx)
        {
          if (!result_in_carry)
            {
              if(!IS_GB)
                genIfxJump (ifx, "m");
              else
                {
                  emit2("rlca");
                  regalloc_dry_run_cost += 1;
                  genIfxJump (ifx, "c");
                }
            }
          else
            genIfxJump (ifx, "c");
        }
      else
        {
          if (!result_in_carry)
            {
              /* Shift the sign bit up into carry */
              emit2 ("rlca");
              regalloc_dry_run_cost += 1;
            }
          outBitC (result);
        }
      /* leave the result in acc */
    }
}

/*-----------------------------------------------------------------*/
/* genCmpGt :- greater than comparison                             */
/*-----------------------------------------------------------------*/
static void
genCmpGt (iCode *ic, iCode *ifx)
{
  operand *left, *right, *result;
  sym_link *letype, *retype;
  int sign;

  left = IC_LEFT (ic);
  right = IC_RIGHT (ic);
  result = IC_RESULT (ic);

  letype = getSpec (operandType (left));
  retype = getSpec (operandType (right));
  sign = !(SPEC_USIGN (letype) | SPEC_USIGN (retype));
  /* assign the asmops */
  aopOp (left, ic, FALSE, FALSE);
  aopOp (right, ic, FALSE, FALSE);
  aopOp (result, ic, TRUE, FALSE);

  setupToPreserveCarry (ic);

  genCmp (right, left, result, ifx, sign);

  _G.preserveCarry = FALSE;
  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genCmpLt - less than comparisons                                */
/*-----------------------------------------------------------------*/
static void
genCmpLt (iCode *ic, iCode *ifx)
{
  operand *left, *right, *result;
  sym_link *letype, *retype;
  int sign;

  left = IC_LEFT (ic);
  right = IC_RIGHT (ic);
  result = IC_RESULT (ic);

  letype = getSpec (operandType (left));
  retype = getSpec (operandType (right));
  sign = !(SPEC_USIGN (letype) | SPEC_USIGN (retype));

  /* assign the asmops */
  aopOp (left, ic, FALSE, FALSE);
  aopOp (right, ic, FALSE, FALSE);
  aopOp (result, ic, TRUE, FALSE);

  setupToPreserveCarry (ic);

  genCmp (left, right, result, ifx, sign);

  _G.preserveCarry = FALSE;
  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* gencjneshort - compare and jump if not equal                    */
/* returns pair that still needs to be popped                      */
/*-----------------------------------------------------------------*/
static PAIR_ID
gencjneshort (operand * left, operand * right, symbol * lbl)
{
  int size = max (AOP_SIZE (left), AOP_SIZE (right));
  int offset = 0;
  unsigned long lit = 0L;

  /* Swap the left and right if it makes the computation easier */
  if (AOP_TYPE (left) == AOP_LIT)
    {
      operand *t = right;
      right = left;
      left = t;
    }

  /* if the right side is a literal then anything goes */
  if (AOP_TYPE (right) == AOP_LIT)
    {
      lit = ulFromVal (AOP (right)->aopu.aop_lit);
      if (lit == 0)
        {
          cheapMove (ASMOP_A, 0, AOP (left), offset);
          if (size > 1)
            {
              while (--size)
                emit3_o (A_OR, ASMOP_A, 0, AOP (left), ++offset);
            }
          else
            emit3 (A_OR, ASMOP_A, ASMOP_A);
          if(!regalloc_dry_run)
            emit2 ("jp NZ,!tlabel", lbl->key + 100);
          regalloc_dry_run_cost += 3;
        }
      else
        {
          while (size--)
            {
              cheapMove (ASMOP_A, 0, AOP (left), offset);
              if ((unsigned int) ((lit >> (offset * 8)) & 0x0FFL) == 0)
                emit3 (A_OR, ASMOP_A, ASMOP_A);
              else
                emit3_o (A_SUB, ASMOP_A, 0, AOP (right), offset);
              if (!regalloc_dry_run)
                emit2 ("jp NZ,!tlabel", lbl->key + 100);
              regalloc_dry_run_cost += 3;
              offset++;
            }
        }
    }
  /* if the right side is in a register or
     pointed to by HL, IX or IY */
  else if (AOP_TYPE (right) == AOP_REG ||
           AOP_TYPE (right) == AOP_HL  ||
           AOP_TYPE (right) == AOP_IY  ||
           AOP_TYPE (right) == AOP_STK ||
           AOP_IS_PAIRPTR (right, PAIR_HL) ||
           AOP_IS_PAIRPTR (right, PAIR_IX) ||
           AOP_IS_PAIRPTR (right, PAIR_IY))
    {
      while (size--)
        {
          cheapMove (ASMOP_A, 0, AOP (left), offset);
          if (AOP_TYPE (right) == AOP_LIT &&
              ((unsigned int) ((lit >> (offset * 8)) & 0x0FFL) == 0))
            {
              emit3 (A_OR, ASMOP_A, ASMOP_A);
              if (!regalloc_dry_run)
                emit2 ("jp NZ,!tlabel", lbl->key + 100);
              regalloc_dry_run_cost += 3;
            }
          else
            {
              emit3_o (A_SUB, ASMOP_A, 0, AOP (right), offset);
              if (!regalloc_dry_run)
                emit2 ("jp NZ,!tlabel", lbl->key + 100);
              regalloc_dry_run_cost += 3;
            }
          offset++;
        }
    }
  /* right is in direct space or a pointer reg, need both a & b */
  else
    {
      PAIR_ID pair;
      for (pair = PAIR_BC; pair <= PAIR_HL; pair++)
        {
          if (((AOP_TYPE (left)  != AOP_PAIRPTR) || (AOP (left)->aopu.aop_pairId  != pair)) &&
              ((AOP_TYPE (right) != AOP_PAIRPTR) || (AOP (right)->aopu.aop_pairId != pair)))
            {
              break;
            }
        }
      _push (pair);
      while (size--)
        {
          emit2 ("; direct compare");
          if(!regalloc_dry_run)
            _emitMove (_pairs[pair].l, aopGet (AOP (left), offset, FALSE));
          else
            regalloc_dry_run_cost += ld_cost(ASMOP_E, AOP (left));
          cheapMove (ASMOP_A, 0, AOP (right), offset);
          emit2 ("sub a,%s", _pairs[pair].l);
          regalloc_dry_run_cost += 1;
          if(!regalloc_dry_run)
            emit2 ("jp NZ,!tlabel", lbl->key + 100);
          regalloc_dry_run_cost += 3;
          offset++;
        }
      return pair;
    }
  return PAIR_INVALID;
}

/*-----------------------------------------------------------------*/
/* gencjne - compare and jump if not equal                         */
/*-----------------------------------------------------------------*/
static void
gencjne (operand * left, operand * right, symbol * lbl)
{
  symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
  PAIR_ID pop;

  pop = gencjneshort (left, right, lbl);

  /* PENDING: ?? */
  if (!regalloc_dry_run)
    {
      emit2 ("ld a,!one");
      emit2 ("jp !tlabel", tlbl->key + 100);
      emitLabel (lbl->key + 100);
      emit2 ("xor a,a");
      emitLabelNoSpill (tlbl->key + 100);
    }
  regalloc_dry_run_cost += 6;
  _pop (pop);
}

/*-----------------------------------------------------------------*/
/* genCmpEq - generates code for equal to                          */
/*-----------------------------------------------------------------*/
static void
genCmpEq (iCode * ic, iCode * ifx)
{
  operand *left, *right, *result;
  bool hl_touched;

  aopOp ((left = IC_LEFT (ic)), ic, FALSE, FALSE);
  aopOp ((right = IC_RIGHT (ic)), ic, FALSE, FALSE);
  aopOp ((result = IC_RESULT (ic)), ic, TRUE, FALSE);

  hl_touched = (AOP_TYPE (IC_LEFT (ic)) == AOP_HL || AOP_TYPE (IC_RIGHT (ic)) == AOP_HL);

  emitDebug ("; genCmpEq: left %u, right %u, result %u", AOP_SIZE(IC_LEFT(ic)), AOP_SIZE(IC_RIGHT(ic)), AOP_SIZE(IC_RESULT(ic)));

  /* Swap operands if it makes the operation easier. ie if:
     1.  Left is a literal.
   */
  if (AOP_TYPE (IC_LEFT (ic)) == AOP_LIT)
    {
      operand *t = IC_RIGHT (ic);
      IC_RIGHT (ic) = IC_LEFT (ic);
      IC_LEFT (ic) = t;
    }

  if (ifx && !AOP_SIZE (result))
    {
      /* if they are both bit variables */
      if (AOP_TYPE (left) == AOP_CRY &&
          ((AOP_TYPE (right) == AOP_CRY) || (AOP_TYPE (right) == AOP_LIT)))
        {
          wassertl (0, "Tried to compare two bits");
        }
      else
        {
          PAIR_ID pop;
          symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
          pop = gencjneshort (left, right, tlbl);
          if (IC_TRUE (ifx))
            {
              if(pop != PAIR_INVALID)
                {
                  emit2 ("pop %s", _pairs[pop].name);
                  regalloc_dry_run_cost += 1;
                }
              if(!regalloc_dry_run)
                emit2 ("jp !tlabel", IC_TRUE (ifx)->key + 100);
              regalloc_dry_run_cost += 3;
              if(!regalloc_dry_run)
                hl_touched ? emitLabel (tlbl->key + 100) : emitLabelNoSpill (tlbl->key + 100);
              else if(hl_touched)
                spillCached();
              _pop (pop);
            }
          else
            {
              /* PENDING: do this better */
              symbol *lbl = regalloc_dry_run ? 0 : newiTempLabel (0);
              if(pop != PAIR_INVALID)
                {
                  emit2 ("pop %s", _pairs[pop].name);
                  regalloc_dry_run_cost += 1;
                }
              if(!regalloc_dry_run)
                emit2 ("jp !tlabel", lbl->key + 100);
              regalloc_dry_run_cost += 3;
              if (!regalloc_dry_run)
                hl_touched ? emitLabel (tlbl->key + 100) : emitLabelNoSpill (tlbl->key + 100);
              else if (hl_touched)
                spillCached();
              _pop (pop);
              if(!regalloc_dry_run)
                {
                  emit2 ("jp !tlabel", IC_FALSE (ifx)->key + 100);
                  emitLabelNoSpill (lbl->key + 100);
                }
              regalloc_dry_run_cost += 3;
            }
        }
      /* mark the icode as generated */
      ifx->generated = 1;
      goto release;
    }

  /* if they are both bit variables */
  if (AOP_TYPE (left) == AOP_CRY &&
      ((AOP_TYPE (right) == AOP_CRY) || (AOP_TYPE (right) == AOP_LIT)))
    {
      wassertl (0, "Tried to compare a bit to either a literal or another bit");
    }
  else
    {
      gencjne (left, right, regalloc_dry_run ? 0 : newiTempLabel (NULL));
      if (AOP_TYPE (result) == AOP_CRY && AOP_SIZE (result))
        {
          wassert (0);
        }
      if (ifx)
        {
          genIfxJump (ifx, "a");
          goto release;
        }
      /* if the result is used in an arithmetic operation
         then put the result in place */
      if (AOP_TYPE (result) != AOP_CRY)
          outAcc (result);
      /* leave the result in acc */
    }

release:
  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* ifxForOp - returns the icode containing the ifx for operand     */
/*-----------------------------------------------------------------*/
iCode *
ifxForOp (operand *op, const iCode *ic)
{
  /* if true symbol then needs to be assigned */
  if (IS_TRUE_SYMOP (op))
    return NULL;

  /* if this has register type condition and
     the next instruction is ifx with the same operand
     and live to of the operand is upto the ifx only then */
  if (ic->next &&
      ic->next->op == IFX &&
      IC_COND (ic->next)->key == op->key &&
      OP_SYMBOL (op)->liveTo <= ic->next->seq)
    return ic->next;

  return NULL;
}

/*-----------------------------------------------------------------*/
/* genAndOp - for && operation                                     */
/*-----------------------------------------------------------------*/
static void
genAndOp (const iCode *ic)
{
  operand *left, *right, *result;

  /* note here that && operations that are in an if statement are
     taken away by backPatchLabels only those used in arthmetic
     operations remain */
  aopOp ((left = IC_LEFT (ic)), ic, FALSE, TRUE);
  aopOp ((right = IC_RIGHT (ic)), ic, FALSE, TRUE);
  aopOp ((result = IC_RESULT (ic)), ic, FALSE, FALSE);

  /* if both are bit variables */
  if (AOP_TYPE (left) == AOP_CRY &&
      AOP_TYPE (right) == AOP_CRY)
    {
      wassertl (0, "Tried to and two bits");
    }
  else
    {
      symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
      _toBoolean (left, TRUE);
      if (!regalloc_dry_run)
        emit2 ("jp Z,!tlabel", tlbl->key + 100);
      regalloc_dry_run_cost += 3;
      _toBoolean (right, FALSE);
      if (!regalloc_dry_run)
        emitLabelNoSpill (tlbl->key + 100);
      outBitAcc (result);
    }

  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genOrOp - for || operation                                      */
/*-----------------------------------------------------------------*/
static void
genOrOp (const iCode *ic)
{
  operand *left, *right, *result;

  /* note here that || operations that are in an
     if statement are taken away by backPatchLabels
     only those used in arthmetic operations remain */
  aopOp ((left = IC_LEFT (ic)), ic, FALSE, TRUE);
  aopOp ((right = IC_RIGHT (ic)), ic, FALSE, TRUE);
  aopOp ((result = IC_RESULT (ic)), ic, FALSE, FALSE);

  /* if both are bit variables */
  if (AOP_TYPE (left) == AOP_CRY &&
      AOP_TYPE (right) == AOP_CRY)
    {
      wassertl (0, "Tried to OR two bits");
    }
  else
    {
      symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
      _toBoolean (left, TRUE);
      if (!regalloc_dry_run)
        emit2 ("jp NZ,!tlabel", tlbl->key + 100);
      regalloc_dry_run_cost += 3;
      _toBoolean (right, FALSE);
      if (!regalloc_dry_run)
        emitLabelNoSpill (tlbl->key + 100);
      outBitAcc (result);
    }

  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* isLiteralBit - test if lit == 2^n                               */
/*-----------------------------------------------------------------*/
static int
isLiteralBit (unsigned long lit)
{
  unsigned long pw[32] =
  {1L, 2L, 4L, 8L, 16L, 32L, 64L, 128L,
   0x100L, 0x200L, 0x400L, 0x800L,
   0x1000L, 0x2000L, 0x4000L, 0x8000L,
   0x10000L, 0x20000L, 0x40000L, 0x80000L,
   0x100000L, 0x200000L, 0x400000L, 0x800000L,
   0x1000000L, 0x2000000L, 0x4000000L, 0x8000000L,
   0x10000000L, 0x20000000L, 0x40000000L, 0x80000000L};
  int idx;

  for (idx = 0; idx < 32; idx++)
    if (lit == pw[idx])
      return idx;
  return -1;
}

/*-----------------------------------------------------------------*/
/* jmpTrueOrFalse -                                                */
/*-----------------------------------------------------------------*/
static void
jmpTrueOrFalse (iCode * ic, symbol * tlbl)
{
  // ugly but optimized by peephole
  // Using emitLabel instead of emitLabelNoSpill (esp. on gbz80)
  // We could jump there from locations with different values in hl.
  // This should be changed to a more efficient solution that spills
  // only what and when necessary.
  if (IC_TRUE (ic))
    { 
      if(!regalloc_dry_run)
        {
          symbol *nlbl = newiTempLabel (NULL);
          emit2 ("jp !tlabel", nlbl->key + 100);
          emitLabel (tlbl->key + 100);
          emit2 ("jp !tlabel", IC_TRUE (ic)->key + 100);
          emitLabel (nlbl->key + 100);
        }
      regalloc_dry_run_cost += 6;
    }
  else
    {
      if(!regalloc_dry_run)
        {
          emit2 ("jp !tlabel", IC_FALSE (ic)->key + 100);
          emitLabel (tlbl->key + 100);
        }
      regalloc_dry_run_cost += 3;
    }
  if(!regalloc_dry_run)
    ic->generated = 1;
}

/*-----------------------------------------------------------------*/
/* genAnd  - code for and                                          */
/*-----------------------------------------------------------------*/
static void
genAnd (const iCode *ic, iCode * ifx)
{
  operand *left, *right, *result;
  int size, offset = 0;
  unsigned long lit = 0L;
  int bytelit = 0;

  aopOp ((left = IC_LEFT (ic)), ic, FALSE, FALSE);
  aopOp ((right = IC_RIGHT (ic)), ic, FALSE, FALSE);
  aopOp ((result = IC_RESULT (ic)), ic, TRUE, FALSE);

  /* if left is a literal & right is not then exchange them */
  if ((AOP_TYPE (left) == AOP_LIT && AOP_TYPE (right) != AOP_LIT) ||
      (AOP_NEEDSACC (right) && !AOP_NEEDSACC (left)))
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  /* if result = right then exchange them */
  if (sameRegs (AOP (result), AOP (right)))
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  /* if right is bit then exchange them */
  if (AOP_TYPE (right) == AOP_CRY &&
      AOP_TYPE (left) != AOP_CRY)
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }
  if (AOP_TYPE (right) == AOP_LIT)
    lit = ulFromVal (AOP (right)->aopu.aop_lit);

  size = AOP_SIZE (result);

  if (AOP_TYPE (left) == AOP_CRY)
    {
      wassertl (0, "Tried to perform an AND with a bit as an operand");
      goto release;
    }

  /* Make sure A is on the left to not overwrite it. */
  if (AOP_TYPE (right) == AOP_ACC ||
    isPair (AOP (right)) && (getPairId (AOP (right)) == PAIR_HL || getPairId (AOP (right)) == PAIR_IY))
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  // if(val & 0xZZ)       - size = 0, ifx != FALSE  -
  // bit = val & 0xZZ     - size = 1, ifx = FALSE -
  if ((AOP_TYPE (right) == AOP_LIT) &&
      (AOP_TYPE (result) == AOP_CRY) &&
      (AOP_TYPE (left) != AOP_CRY))
    {
      symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
      int sizel;

      sizel = AOP_SIZE (left);
      if (size)
        {
          /* PENDING: Test case for this. */
          emit2 ("scf");
          regalloc_dry_run_cost += 1;
        }
      while (sizel--)
        {
          if ((bytelit = ((lit >> (offset * 8)) & 0x0FFL)) != 0x0L)
            {
              cheapMove (ASMOP_A, 0, AOP (left), offset);
              if (bytelit != 0x0FFL)
                emit3_o (A_AND, ASMOP_A, 0, AOP (right), offset);
              else
                {
                  /* For the flags */
                  emit3 (A_OR, ASMOP_A, ASMOP_A);
                }
              if (size || ifx)  /* emit jmp only, if it is actually used */
                {
                  if (!regalloc_dry_run)
                    emit2 ("jp NZ,!tlabel", tlbl->key + 100);
                  regalloc_dry_run_cost += 3;
                }
            }
            offset++;
        }
      // bit = left & literal
      if (size)
        {
          emit2 ("clr c");
          if (!regalloc_dry_run)
            emit2 ("!tlabeldef", tlbl->key + 100);
          regalloc_dry_run_cost += 3;
          _G.lines.current->isLabel = 1;
        }
      // if(left & literal)
      else
        {
          if (ifx)
            {
              jmpTrueOrFalse (ifx, tlbl);
            }
          goto release;
        }
      outBitC (result);
      goto release;
    }

  if (IS_R2K && isPair (AOP (result)) && 
     (getPairId (AOP (result)) == PAIR_HL && isPair (AOP (right)) && getPairId (AOP (right)) == PAIR_DE ||
     getPairId (AOP (result)) == PAIR_HL && isPair (AOP (left)) && getPairId (AOP (left)) == PAIR_DE ||
     isPair (AOP (left)) && getPairId (AOP (left)) == PAIR_IY && getPairId (AOP (result)) == PAIR_IY && isPair (AOP (right)) && getPairId (AOP (right)) == PAIR_DE))
    {
      if (isPair (AOP (left)) && getPairId (AOP (left)) == PAIR_DE)
        fetchPair (PAIR_HL, AOP (right));
      else /* right operand in DE */
        fetchPair (getPairId (AOP (result)), AOP (left));
      emit2 ("and hl, de");
      regalloc_dry_run_cost += (getPairId (AOP (result)) == PAIR_HL ? 1 : 2);
      goto release;
    }

  /* if left is same as result */
  if (sameRegs (AOP (result), AOP (left)))
    {
      for (; size--; offset++)
        {
          if (AOP_TYPE (right) == AOP_LIT)
            {
              bytelit = (lit >> (offset * 8)) & 0x0FFL;
              if (bytelit == 0x0FF)
                continue;
              else if (bytelit == 0)
                aopPut3 (AOP (result), offset, ASMOP_ZERO, 0);
              else
                {
                  cheapMove (ASMOP_A, 0, AOP (left), offset);
                  if (isLiteralBit (~bytelit & 0x0FFL) >= 0)
                    {
                      emit2 ("res %d, a", isLiteralBit (~bytelit & 0x0FFL));
                      regalloc_dry_run_cost += 2;
                    }
                  else
                    emit3_o (A_AND, ASMOP_A, 0, AOP (right), offset);
                  cheapMove (AOP (left), offset, ASMOP_A, 0);
                }
            }
          else
            {
              cheapMove (ASMOP_A, 0, AOP (left), offset);
              emit3_o (A_AND, ASMOP_A, 0, AOP (right), offset);
              cheapMove (AOP (left), offset, ASMOP_A, 0);
            }
        }
    }
  else
    {
      // left & result in different registers
      if (AOP_TYPE (result) == AOP_CRY)
        {
          wassertl (0, "Tried to AND where the result is in carry");
        }
      else
        {
          for (; (size--); offset++)
            {
              // normal case
              // result = left & right
              if (AOP_TYPE (right) == AOP_LIT)
                {
                  if ((bytelit = (int) ((lit >> (offset * 8)) & 0x0FFL)) == 0x0FF)
                    {
                      cheapMove (AOP (result), offset, AOP (left), offset);
                      continue;
                    }
                  else if (bytelit == 0)
                    {
                      aopPut3 (AOP (result), offset, ASMOP_ZERO, 0);
                      continue;
                    }
                }
              // faster than result <- left, anl result,right
              // and better if result is SFR
              if (AOP_TYPE (left) == AOP_ACC)
                emit3_o (A_AND, ASMOP_A, 0, AOP (right), offset);
              else
                {
                  cheapMove (ASMOP_A, 0, AOP (left), offset);
                  emit3_o (A_AND, ASMOP_A, 0, AOP (right), offset);
                }
              cheapMove (AOP (result), offset, ASMOP_A, 0);
            }
        }
    }

release:
  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genOr  - code for or                                            */
/*-----------------------------------------------------------------*/
static void
genOr (const iCode *ic, iCode * ifx)
{
  operand *left, *right, *result;
  int size, offset = 0;
  unsigned long lit = 0L;
  int bytelit = 0;

  aopOp ((left = IC_LEFT (ic)), ic, FALSE, FALSE);
  aopOp ((right = IC_RIGHT (ic)), ic, FALSE, FALSE);
  aopOp ((result = IC_RESULT (ic)), ic, TRUE, FALSE);

  /* if left is a literal & right is not then exchange them */
  if ((AOP_TYPE (left) == AOP_LIT && AOP_TYPE (right) != AOP_LIT) ||
      (AOP_NEEDSACC (right) && !AOP_NEEDSACC (left)))
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  /* if result = right then exchange them */
  if (sameRegs (AOP (result), AOP (right)))
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  /* if right is bit then exchange them */
  if (AOP_TYPE (right) == AOP_CRY &&
      AOP_TYPE (left) != AOP_CRY)
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }
  if (AOP_TYPE (right) == AOP_LIT)
    lit = ulFromVal (AOP (right)->aopu.aop_lit);

  size = AOP_SIZE (result);

  if (AOP_TYPE (left) == AOP_CRY)
    {
      wassertl (0, "Tried to OR where left is a bit");
      goto release;
    }

  /* Make sure A is on the left to not overwrite it. */
  if (AOP_TYPE (right) == AOP_ACC)
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  // if(val | 0xZZ)       - size = 0, ifx != FALSE  -
  // bit = val | 0xZZ     - size = 1, ifx = FALSE -
  if ((AOP_TYPE (right) == AOP_LIT) &&
      (AOP_TYPE (result) == AOP_CRY) &&
      (AOP_TYPE (left) != AOP_CRY))
    {
      symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
      int sizel;

      sizel = AOP_SIZE (left);

      if (size)
        {
          wassertl (0, "Result is assigned to a bit");
        }
      /* PENDING: Modeled after the AND code which is inefficient. */
      while (sizel--)
        {
          bytelit = (lit >> (offset * 8)) & 0x0FFL;

          cheapMove (ASMOP_A, 0, AOP (left), offset);

          if (bytelit != 0)
            emit3_o (A_OR, ASMOP_A, 0, AOP (right), offset);
          else if (ifx)
            {
              /* For the flags */
              emit3 (A_OR, ASMOP_A, ASMOP_A);
            }

          if (ifx)  /* emit jmp only, if it is actually used */
            {
              if(!regalloc_dry_run)
                emit2 ("jp NZ,!tlabel", tlbl->key + 100);
              regalloc_dry_run_cost += 3;
            }

          offset++;
        }
      if (ifx)
        {
          jmpTrueOrFalse (ifx, tlbl);
        }
      goto release;
    }

  /* if left is same as result */
  if (sameRegs (AOP (result), AOP (left)))
    {
      for (; size--; offset++)
        {
          if (AOP_TYPE (right) == AOP_LIT)
            {
              bytelit = (lit >> (offset * 8)) & 0x0FFL;
              if (bytelit == 0x00L)
                continue;
              else
                {
                  cheapMove (ASMOP_A, 0, AOP (left), offset);
                  if (isLiteralBit(bytelit) >= 0)
                    emit2 ("set %d, a", isLiteralBit(bytelit));
                  else
                    emit3_o(A_OR, ASMOP_A, 0, AOP (right), offset);
                  cheapMove (AOP (result), offset, ASMOP_A, 0);
                }
            }
          else
            {
              cheapMove (ASMOP_A, 0, AOP (left), offset);
              emit3_o (A_OR, ASMOP_A, 0, AOP (right), offset);
              cheapMove (AOP (result), offset, ASMOP_A, 0);
            }
        }
    }
  else
    {
      // left & result in different registers
      if (AOP_TYPE (result) == AOP_CRY)
        {
          wassertl (0, "Result of OR is in a bit");
        }
      else
        for (; (size--); offset++)
          {
            // normal case
            // result = left & right
            if (AOP_TYPE (right) == AOP_LIT)
              {
                if (((lit >> (offset * 8)) & 0x0FFL) == 0x00L)
                  {
                    cheapMove (AOP (result), offset, AOP (left), offset);
                    continue;
                  }
              }
            // This is a bit broken, there will be problems for y_0 = x_0 | z_0, x_0 = y_0 | z_1 as either order of the two byte ors will result in the result destroying the second part of the operand. Currently, we use a workaround in the register allocator to avoid this. See also the comment on the 2-byte addition workaround above.
            if(AOP_TYPE (left) != AOP_ACC)
              cheapMove (ASMOP_A, 0, AOP (left), offset);
            if(AOP_TYPE (right) == AOP_LIT && isLiteralBit(((lit >> (offset * 8)) & 0x0FFL)) >= 0)
              emit2 ("set %d, a", isLiteralBit(((lit >> (offset * 8)) & 0x0FFL)));
            else
              emit3_o (A_OR, ASMOP_A, 0, AOP (right), offset);
            cheapMove (AOP (result), offset, ASMOP_A, 0);
            /* PENDING: something weird is going on here.  Add exception. */
            if (AOP_TYPE (result) == AOP_ACC)
              break;
          }
    }

release:
  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genXor - code for xclusive or                                   */
/*-----------------------------------------------------------------*/
static void
genXor (const iCode *ic, iCode * ifx)
{
  operand *left, *right, *result;
  int size, offset = 0;
  unsigned long lit = 0L;

  aopOp ((left = IC_LEFT (ic)), ic, FALSE, FALSE);
  aopOp ((right = IC_RIGHT (ic)), ic, FALSE, FALSE);
  aopOp ((result = IC_RESULT (ic)), ic, TRUE, FALSE);

  /* if left is a literal & right is not then exchange them */
  if ((AOP_TYPE (left) == AOP_LIT && AOP_TYPE (right) != AOP_LIT) ||
      (AOP_NEEDSACC (right) && !AOP_NEEDSACC (left)))
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  /* if result = right then exchange them */
  if (sameRegs (AOP (result), AOP (right)))
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }

  /* if right is bit then exchange them */
  if (AOP_TYPE (right) == AOP_CRY &&
      AOP_TYPE (left) != AOP_CRY)
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }
  if (AOP_TYPE (right) == AOP_LIT)
    lit = ulFromVal (AOP (right)->aopu.aop_lit);

  size = AOP_SIZE (result);

  if (AOP_TYPE (left) == AOP_CRY)
    {
      wassertl (0, "Tried to XOR a bit");
      goto release;
    }

  /* Make sure A is on the left to not overwrite it. */
  if (AOP_TYPE (right) == AOP_ACC)
    {
      operand *tmp = right;
      right = left;
      left = tmp;
    }
 
  // if(val & 0xZZ)       - size = 0, ifx != FALSE  -
  // bit = val & 0xZZ     - size = 1, ifx = FALSE -
  if ((AOP_TYPE (right) == AOP_LIT) &&
      (AOP_TYPE (result) == AOP_CRY) &&
      (AOP_TYPE (left) != AOP_CRY))
    {
      symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
      int sizel;

      sizel = AOP_SIZE (left);

      if (size)
        {
          /* PENDING: Test case for this. */
          wassertl (0, "Tried to XOR left against a literal with the result going into a bit");
        }
      while (sizel--)
        {
          cheapMove (ASMOP_A, 0, AOP (left), offset);
          emit3_o (A_XOR, ASMOP_A, 0, AOP (right), offset);
          if (ifx)      /* emit jmp only, if it is actually used * */
            if(!regalloc_dry_run)
              emit2 ("jp NZ,!tlabel", tlbl->key + 100);
            regalloc_dry_run_cost += 3;
          offset++;
        }
      if (ifx)
        {
          jmpTrueOrFalse (ifx, tlbl);
        }
      else if(size)
        {
          wassertl (0, "Result of XOR was destined for a bit");
        }
      goto release;
    }

  /* if left is same as result */
  if (sameRegs (AOP (result), AOP (left)))
    {
      for (; size--; offset++)
        {
          if (AOP_TYPE (right) == AOP_LIT)
            {
              if (((lit >> (offset * 8)) & 0x0FFL) == 0x00L)
                continue;
              else
                {
                  cheapMove (ASMOP_A, 0, AOP (left), offset);
                  emit3_o (A_XOR, ASMOP_A, 0, AOP (right), offset);
                  cheapMove (AOP (result), offset, ASMOP_A, 0);
                }
            }
          else
            {
              if (AOP_TYPE (left) == AOP_ACC)
                emit3_o (A_XOR, ASMOP_A, 0, AOP (right), offset);
              else
                {
                  cheapMove (ASMOP_A, 0, AOP (left), offset);
                  emit3_o (A_XOR, ASMOP_A, 0, AOP (right), offset);
                  cheapMove (AOP (result), offset, ASMOP_A, 0);
                }
            }
        }
    }
  else
    {
      // left & result in different registers
      if (AOP_TYPE (result) == AOP_CRY)
        {
          wassertl (0, "Result of XOR is in a bit");
        }
      else
        for (; (size--); offset++)
          {
            // normal case
            // result = left & right
            if (AOP_TYPE (right) == AOP_LIT)
              {
                if (((lit >> (offset * 8)) & 0x0FFL) == 0x00L)
                  {
                    cheapMove (AOP (result), offset, AOP (left), offset);
                    continue;
                  }
              }
            // faster than result <- left, anl result,right
            // and better if result is SFR
            if (AOP_TYPE (left) == AOP_ACC)
              emit3_o (A_XOR, ASMOP_A, 0, AOP (right), offset);
            else
              {
                cheapMove (ASMOP_A, 0, AOP (left), offset);
                emit3_o (A_XOR, ASMOP_A, 0, AOP (right), offset);
              }
            cheapMove (AOP (result), offset, ASMOP_A, 0);
          }
    }

release:
  freeAsmop (left, NULL, ic);
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genInline - write the inline code out                           */
/*-----------------------------------------------------------------*/
static void
genInline (const iCode *ic)
{
  char *buffer, *bp, *bp1;
  bool inComment = FALSE;

  _G.lines.isInline += (!options.asmpeep);

  buffer = bp = bp1 = Safe_strdup (IC_INLINE (ic));

  /* emit each line as a code */
  while (*bp)
    {
      switch (*bp)
        {
        case ';':
          inComment = TRUE;
          ++bp;
          break;

        case '\x87':
        case '\n':
          inComment = FALSE;
          *bp++ = '\0';
          /* Don't emit whitespace */
          while(isspace(*bp1))
            bp1++;
          if(*bp1)
            emit2 (bp1);
          bp1 = bp;
          break;

        default:
          /* Add \n for labels, not dirs such as c:\mydir */
          if (!inComment && (*bp == ':') && (isspace((unsigned char)bp[1])))
            {
              ++bp;
              *bp = '\0';
              ++bp;
              emit2 (bp1);
              bp1 = bp;
            }
          else
            ++bp;
          break;
        }
    }
  if (bp1 != bp)
    {
      while(isspace(*bp1))
        bp1++;
      if(*bp1)
        emit2 (bp1);
    }

  Safe_free (buffer);

  _G.lines.isInline -= (!options.asmpeep);

}

/*-----------------------------------------------------------------*/
/* genRRC - rotate right with carry                                */
/*-----------------------------------------------------------------*/
static void
genRRC (const iCode *ic)
{
  wassert (0);
}

/*-----------------------------------------------------------------*/
/* genRLC - generate code for rotate left with carry               */
/*-----------------------------------------------------------------*/
static void
genRLC (const iCode *ic)
{
  wassert (0);
}

/*-----------------------------------------------------------------*/
/* genGetHbit - generates code get highest order bit               */
/*-----------------------------------------------------------------*/
static void
genGetHbit (const iCode *ic)
{
  operand *left, *result;
  left = IC_LEFT (ic);
  result = IC_RESULT (ic);

  aopOp (left, ic, FALSE, FALSE);
  aopOp (result, ic, FALSE, FALSE);

  /* get the highest order byte into a */
  cheapMove (ASMOP_A, 0, AOP (left), AOP_SIZE (left) - 1);

  if (AOP_TYPE (result) == AOP_CRY)
    {
      emit3 (A_RL, ASMOP_A, 0);
      outBitC (result);
    }
  else
    {
      emit3 (A_RLC, ASMOP_A, 0);
      emit2 ("and a,!one");
      regalloc_dry_run_cost += 2;
      outAcc (result);
    }


  freeAsmop (left, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genGetAbit - generates code get a single bit                    */
/*-----------------------------------------------------------------*/
static void
genGetAbit (const iCode *ic)
{
  wassert (0);
}

static void
emitRsh2 (asmop *aop, int size, int is_signed)
{
  int offset = 0;

  while (size--)
    {
      if (offset == 0)
        emit3_o (is_signed ? A_SRA : A_SRL, aop, size, 0, 0);
      else
        emit3_o (A_RR, aop, size, 0, 0);
      offset++;
    }
}

/*-----------------------------------------------------------------*/
/* shiftR2Left2Result - shift right two bytes from left to result  */
/*-----------------------------------------------------------------*/
static void
shiftR2Left2Result (const iCode *ic, operand * left, int offl,
                    operand * result, int offr,
                    int shCount, int is_signed)
{
  int size = 2;
  symbol *tlbl;
  
  if (IS_R2K && !is_signed && shCount >= 2 && isPairDead (PAIR_HL, ic) &&
    ((isPair (AOP (left)) && getPairId (AOP (left)) == PAIR_HL || isPair (AOP (result)) && getPairId (AOP (result)) == PAIR_HL) && isPairDead (PAIR_DE, ic) ||
    isPair (AOP (left)) && getPairId (AOP (left)) == PAIR_DE))
    {
      bool op_de = (getPairId (AOP (left)) == PAIR_DE);
      if(op_de)
        emit2 ("ld hl, !immedword", 0xffff >> shCount);
      else
        {
          fetchPair (PAIR_HL, AOP (left));
          emit2 ("ld de, !immedword", 0xffff >> shCount);
        }
      regalloc_dry_run_cost += 3;
      while(shCount--)
        {
          if(op_de)
            emit2 ("rr de");
          else
            emit2 ("rr hl");
          regalloc_dry_run_cost++;
        }
      emit2 ("and hl, de");
      regalloc_dry_run_cost += 1;
      commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
      return;
    }

  movLeft2Result (left, offl, result, offr, 0);
  movLeft2Result (left, offl + 1, result, offr + 1, 0);

  if (shCount == 0)
    return;

  /*  if (AOP(result)->type == AOP_REG) { */

  tlbl = regalloc_dry_run ? 0 : newiTempLabel (NULL);

  /* Left is already in result - so now do the shift */
  /* Optimizing for speed by default. */
  if (!optimize.codeSize || shCount <= 2)
    {
      while (shCount--)
        {
          emitRsh2 (AOP (result), size, is_signed);
        }
    }
  else
    {
      if(!regalloc_dry_run)
        {
          emit2 ("ld a,!immedbyte", shCount);
          emitLabelNoSpill (tlbl->key + 100);
        }
      regalloc_dry_run_cost += 2;

      emitRsh2 (AOP (result), size, is_signed);

      if(!regalloc_dry_run)
        {
          emit2 ("dec a");
          emit2 ("jp NZ,!tlabel", tlbl->key + 100);
        }
      regalloc_dry_run_cost += 4;
    }
}

/*-----------------------------------------------------------------*/
/* shiftL2Left2Result - shift left two bytes from left to result   */
/*-----------------------------------------------------------------*/
static void
shiftL2Left2Result (operand * left, int offl,
                    operand * result, int offr, int shCount)
{
  if (sameRegs (AOP (result), AOP (left)) &&
      ((offl + MSB16) == offr))
    {
      wassert (0);
    }
  else
    {
      /* Copy left into result */
      movLeft2Result (left, offl, result, offr, 0);
      movLeft2Result (left, offl + 1, result, offr + 1, 0);
    }

  if (shCount == 0)
    return;

  if (getPairId (AOP (result)) == PAIR_HL)
    {
      while (shCount--)
        {
          emit2 ("add hl, hl");
          regalloc_dry_run_cost += 1;
        }
    }
  else if (getPairId (AOP (result)) == PAIR_IY)
    {
      while (shCount--)
        {
          emit2 ("add iy, iy");
          regalloc_dry_run_cost += 2;
        }
    }
  else
    {
    int size = 2;
    int offset = 0;
    symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);
    symbol *tlbl1 = regalloc_dry_run ? 0 : newiTempLabel (0);

    if (AOP (result)->type == AOP_REG)
      {
        while (shCount--)
          {
            for (offset = 0; offset < size; offset++)
              emit3_o (offset ? A_RL : A_SLA, AOP (result), offset, 0, 0);
          }
      }
    else
      {
        /* Left is already in result - so now do the shift */
        if (shCount > 1)
          {
            if (!regalloc_dry_run)
              {
                emit2 ("ld a,!immedbyte+1", shCount);
                emit2 ("jp !tlabel", tlbl1->key + 100);
                emitLabelNoSpill (tlbl->key + 100);
              }
            regalloc_dry_run_cost += 4;
          }

        while (size--)
          {
            emit3_o (offset ? A_RL : A_SLA, AOP (result), offset, 0, 0);

            offset++;
          }
        if (shCount > 1)
          {
            if (!regalloc_dry_run)
              {
                emitLabelNoSpill (tlbl1->key + 100);
                emit2 ("dec a");
                emit2 ("jp NZ,!tlabel", tlbl->key + 100);
              }
            regalloc_dry_run_cost += 4;
          }
      }
  }
}

/*-----------------------------------------------------------------*/
/* AccRol - rotate left accumulator by known count                 */
/*-----------------------------------------------------------------*/
static void
AccRol (int shCount)
{
  shCount &= 0x0007;            // shCount : 0..7

  switch (shCount)
    {
    case 4:
      emit3 (A_RLCA, 0, 0);
    case 3:
      emit3 (A_RLCA, 0, 0);
    case 2:
      emit3 (A_RLCA, 0, 0);
    case 1:
      emit3 (A_RLCA, 0, 0);
    case 0:
      break;
    case 5:
      emit3 (A_RRCA, 0 ,0);
    case 6:
      emit3 (A_RRCA, 0 ,0);
    case 7:
      emit3 (A_RRCA, 0 ,0);
      break;
    }
}

/*-----------------------------------------------------------------*/
/* AccLsh - left shift accumulator by known count                  */
/*-----------------------------------------------------------------*/
static void
AccLsh (int shCount)
{
  static const unsigned char SLMask[] =
    {
      0xFF, 0xFE, 0xFC, 0xF8, 0xF0, 0xE0, 0xC0, 0x80, 0x00
    };

  if (shCount != 0)
    {
      if (shCount == 1)
        {
          emit3 (A_ADD, ASMOP_A, ASMOP_A);
        }
      else if (shCount == 2)
        {
          emit3 (A_ADD, ASMOP_A, ASMOP_A);
          emit3 (A_ADD, ASMOP_A, ASMOP_A);
        }
      else
        {
          /* rotate left accumulator */
          AccRol (shCount);
          /* and kill the lower order bits */
          emit2 ("and a,!immedbyte", SLMask[shCount]);
          regalloc_dry_run_cost += 2;
        }
    }
}

/*-----------------------------------------------------------------*/
/* shiftL1Left2Result - shift left one byte from left to result    */
/*-----------------------------------------------------------------*/
static void
shiftL1Left2Result (operand * left, int offl,
                    operand * result, int offr, int shCount)
{
  /* If operand and result are the same we can shift in place.
     However shifting in acc using add is cheaper than shifting
     in place using sla; when shifting by more than 2 shifting in
     acc is worth the additional effort for loading from/to acc. */
  if (sameRegs (AOP (left), AOP (result)) && shCount <= 2 && offr == offl)
    {
      while (shCount--)
        emit3 (A_SLA, AOP (result), 0);
    }
  else
    {
      cheapMove (ASMOP_A, 0, AOP (left), offl);
      /* shift left accumulator */
      AccLsh (shCount);
      cheapMove (AOP (result), offr, ASMOP_A, 0);
    }
}

/*-----------------------------------------------------------------*/
/* genlshTwo - left shift two bytes by known amount                */
/*-----------------------------------------------------------------*/
static void
genlshTwo (operand * result, operand * left, int shCount)
{
  int size = AOP_SIZE (result);

  wassert (size == 2);

  /* if shCount >= 8 */
  if (shCount >= 8)
    {
      shCount -= 8;
      if (size > 1)
        {
          if (shCount)
            {
              movLeft2Result (left, LSB, result, MSB16, 0);
              shiftL1Left2Result (left, LSB, result, MSB16, shCount);
              aopPut3 (AOP (result), LSB, ASMOP_ZERO, 0);
            }
          else
            {
              movLeft2Result (left, LSB, result, MSB16, 0);
              aopPut3 (AOP (result), 0, ASMOP_ZERO, 0);
            }
        }
      else
        aopPut3 (AOP (result), LSB, ASMOP_ZERO, 0);
    }
  /*  0 <= shCount <= 7 */
  else
    {
      if (size == 1)
        {
          wassert (0);
        }
      else
        {
          shiftL2Left2Result (left, LSB, result, LSB, shCount);
        }
    }
}

/*-----------------------------------------------------------------*/
/* genlshOne - left shift a one byte quantity by known count       */
/*-----------------------------------------------------------------*/
static void
genlshOne (operand * result, operand * left, int shCount)
{
  shiftL1Left2Result (left, LSB, result, LSB, shCount);
}

/*-----------------------------------------------------------------*/
/* genLeftShiftLiteral - left shifting by known count              */
/*-----------------------------------------------------------------*/
static void
genLeftShiftLiteral (operand *left,
                     operand *right,
                     operand *result,
                     const iCode *ic)
{
  int shCount = (int) ulFromVal (AOP (right)->aopu.aop_lit);
  int size;

  freeAsmop (right, NULL, ic);

  aopOp (left, ic, FALSE, FALSE);
  aopOp (result, ic, FALSE, FALSE);

  size = getSize (operandType (result));

  /* I suppose that the left size >= result size */

  if (shCount >= (size * 8))
    {
      while (size--)
        aopPut3 (AOP (result), size, ASMOP_ZERO, 0);
    }
  else
    {
      switch (size)
        {
        case 1:
          genlshOne (result, left, shCount);
          break;
        case 2:
          genlshTwo (result, left, shCount);
          break;
        case 4:
          wassertl (0, "Shifting of longs is currently unsupported");
          break;
        default:
          wassert (0);
        }
    }
  freeAsmop (left, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genLeftShift - generates code for left shifting                 */
/*-----------------------------------------------------------------*/
static void
genLeftShift (const iCode *ic)
{
  int size, offset;
  symbol *tlbl = 0, *tlbl1 = 0;
  operand *left, *right, *result;

  right = IC_RIGHT (ic);
  left = IC_LEFT (ic);
  result = IC_RESULT (ic);

  aopOp (right, ic, FALSE, FALSE);

  /* if the shift count is known then do it
     as efficiently as possible */
  if (AOP_TYPE (right) == AOP_LIT)
    {
      genLeftShiftLiteral (left, right, result, ic);
      freeAsmop (right, NULL, ic);
      return;
    }

  /* shift count is unknown then we have to form a loop get the loop
     count in B : Note: we take only the lower order byte since
     shifting more that 32 bits make no sense anyway, ( the largest
     size of an object can be only 32 bits ) */
  cheapMove (ASMOP_A, 0, AOP (right), 0);
  emit2 ("inc a");
  regalloc_dry_run_cost += 1;
  freeAsmop (right, NULL, ic);
  aopOp (left, ic, FALSE, FALSE);
  aopOp (result, ic, FALSE, FALSE);

  if (AOP_TYPE (left) != AOP_REG || AOP_TYPE (result) != AOP_REG)
    _push (PAIR_AF);

  /* now move the left to the result if they are not the
     same */

  if (!sameRegs (AOP (left), AOP (result)))
    {

      size = AOP_SIZE (result);
      offset = 0;
      while (size--)
        {
          cheapMove (AOP (result), offset, AOP (left), offset);
          offset++;
        }
    }

  if(!regalloc_dry_run)
    {
      tlbl = newiTempLabel (NULL);
      tlbl1 = newiTempLabel (NULL);
    }
  size = AOP_SIZE (result);
  offset = 0;

  if (AOP_TYPE (left) != AOP_REG || AOP_TYPE (result) != AOP_REG)
     _pop (PAIR_AF);

  if(!regalloc_dry_run)
    {
      emit2 ("jp !tlabel", tlbl1->key + 100);
      emitLabelNoSpill (tlbl->key + 100);
    }
  regalloc_dry_run_cost += 3;

  while (size--)
    {
      emit3_o (offset ? A_RL : A_SLA, AOP (result), offset, 0, 0);
      offset++;
    }

  if(!regalloc_dry_run)
    {
      emitLabelNoSpill (tlbl1->key + 100);
      emit2 ("dec a");
      emit2 ("jp NZ,!tlabel", tlbl->key + 100);
    }
  regalloc_dry_run_cost += 4;

  freeAsmop (left, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genrshOne - left shift two bytes by known amount != 0           */
/*-----------------------------------------------------------------*/
static void
genrshOne (operand * result, operand * left, int shCount, int is_signed)
{
  /* Errk */
  int size = AOP_SIZE (result);

  wassert (size == 1);
  wassert (shCount < 8);

  if (AOP (result)->type == AOP_REG)
    {
      cheapMove (AOP (result), 0, AOP (left), 0);
      while (shCount--)
        emit3 (is_signed ? A_SRA : A_SRL, AOP (result), 0);
    }
  else
    {
      cheapMove (ASMOP_A, 0, AOP (left), 0);
      while (shCount--)
        emit3 (is_signed ? A_SRA : A_SRL, ASMOP_A, 0);
      cheapMove (AOP (result), 0, ASMOP_A, 0);
    }
}

/*-----------------------------------------------------------------*/
/* AccRsh - right shift accumulator by known count                 */
/*-----------------------------------------------------------------*/
static void
AccRsh (int shCount)
{
  static const unsigned char SRMask[] =
    {
      0xFF, 0x7F, 0x3F, 0x1F, 0x0F, 0x07, 0x03, 0x01, 0x00
    };

  if (shCount != 0)
    {
      /* rotate right accumulator */
      AccRol (8 - shCount);
      /* and kill the higher order bits */
      if(!regalloc_dry_run)
        emit2 ("and a,!immedbyte", SRMask[shCount]);
      regalloc_dry_run_cost += 2;
    }
}

/*-----------------------------------------------------------------*/
/* shiftR1Left2Result - shift right one byte from left to result   */
/*-----------------------------------------------------------------*/
static void
shiftR1Left2Result (operand * left, int offl,
                    operand * result, int offr,
                    int shCount, int sign)
{
  cheapMove (ASMOP_A, 0, AOP (left), offl);
  if (sign)
    {
      while (shCount--)
        emit3 (sign ? A_SRA : A_SRL, ASMOP_A, 0);
    }
  else
    AccRsh (shCount);
  cheapMove (AOP (result), offr, ASMOP_A, 0);
}

/*-----------------------------------------------------------------*/
/* genrshTwo - right shift two bytes by known amount               */
/*-----------------------------------------------------------------*/
static void
genrshTwo (const iCode *ic, operand * result, operand * left,
           int shCount, int sign)
{
  /* if shCount >= 8 */
  if (shCount >= 8)
    {
      shCount -= 8;
      if (shCount)
        {
          shiftR1Left2Result (left, MSB16, result, LSB,
                              shCount, sign);
        }
      else
        {
          movLeft2Result (left, MSB16, result, LSB, sign);
        }
      if (sign)
        {
          /* Sign extend the result */
          cheapMove (ASMOP_A, 0, AOP (result), 0);
          emit3 (A_RLC, ASMOP_A, 0);
          emit3 (A_SBC, ASMOP_A, ASMOP_A);
          cheapMove (AOP (result), MSB16, ASMOP_A, 0);
        }
      else
        aopPut3 (AOP (result), 1, ASMOP_ZERO, 0);
    }
  /*  0 <= shCount <= 7 */
  else
    shiftR2Left2Result (ic, left, LSB, result, LSB, shCount, sign);
}

/*-----------------------------------------------------------------*/
/* genRightShiftLiteral - right shifting by known count              */
/*-----------------------------------------------------------------*/
static void
genRightShiftLiteral (operand *left,
                      operand *right,
                      operand *result,
                      const iCode *ic,
                      int sign)
{
  int shCount = (int) ulFromVal (AOP (right)->aopu.aop_lit);
  int size;

  freeAsmop (right, NULL, ic);

  aopOp (left, ic, FALSE, FALSE);
  aopOp (result, ic, FALSE, FALSE);

  size = getSize (operandType (result));

  /* I suppose that the left size >= result size */

  if (shCount >= (size * 8)) {
    asmop *s;
    if (!SPEC_USIGN(getSpec(operandType(left)))) {
      cheapMove (ASMOP_A, 0, AOP (left), 0);
      emit3 (A_RLC, ASMOP_A, 0);
      emit3 (A_SBC, ASMOP_A, ASMOP_A);
      s=ASMOP_A;
    } else {
      s=ASMOP_ZERO;
    }
    while (size--)
      cheapMove (AOP (result), size, s, 0);
  }
  else
    {
      switch (size)
        {
        case 1:
          genrshOne (result, left, shCount, sign);
          break;
        case 2:
          genrshTwo (ic, result, left, shCount, sign);
          break;
        case 4:
          wassertl (0, "Asked to shift right a long which should be a function call");
          break;
        default:
          wassertl (0, "Entered default case in right shift delegate");
        }
    }
  freeAsmop (left, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genRightShift - generate code for right shifting                */
/*-----------------------------------------------------------------*/
static void
genRightShift (const iCode *ic)
{
  operand *right, *left, *result;
  sym_link *retype;
  int size, offset, first = 1;
  bool is_signed;

  symbol *tlbl = 0, *tlbl1 = 0;

  /* if signed then we do it the hard way preserve the
     sign bit moving it inwards */
  retype = getSpec (operandType (IC_RESULT (ic)));

  is_signed = !SPEC_USIGN (retype);

  right = IC_RIGHT (ic);
  left = IC_LEFT (ic);
  result = IC_RESULT (ic);

  aopOp (right, ic, FALSE, FALSE);

  /* if the shift count is known then do it
     as efficiently as possible */
  if (AOP_TYPE (right) == AOP_LIT)
    {
      genRightShiftLiteral (left, right, result, ic, is_signed);
      freeAsmop (right, NULL, ic);
      return;
    }

  cheapMove (ASMOP_A, 0, AOP (right), 0);
  emit2 ("inc a");
  regalloc_dry_run_cost += 1;
  freeAsmop (right, NULL, ic);

  aopOp (left, ic, FALSE, FALSE);
  aopOp (result, ic, FALSE, FALSE);

  if (AOP_TYPE (left) != AOP_REG || AOP_TYPE (result) != AOP_REG)
     _push (PAIR_AF);

  /* now move the left to the result if they are not the
     same */
  if (!sameRegs (AOP (left), AOP (result)))
    {

      size = AOP_SIZE (result);
      offset = 0;
      while (size--)
        {
          cheapMove (AOP (result), offset, AOP (left), offset);
          offset++;
        }
    }

  if (!regalloc_dry_run)
    {
      tlbl = newiTempLabel (NULL);
      tlbl1 = newiTempLabel (NULL);
    }
  size = AOP_SIZE (result);
  offset = size - 1;

  if (AOP_TYPE (left) != AOP_REG || AOP_TYPE (result) != AOP_REG)
     _pop (PAIR_AF);

  if(!regalloc_dry_run)
    {
      emit2 ("jp !tlabel", tlbl1->key + 100);
      emitLabelNoSpill (tlbl->key + 100);
    }
  regalloc_dry_run_cost += 3;
  
  while (size--)
    {
      if (first)
        {
          emit3_o (is_signed ? A_SRA : A_SRL, AOP (result), offset, 0, 0);
          first = 0;
        }
      else
        {
          emit3_o (A_RR, AOP (result), offset, 0, 0);
        }
      offset--;
    }
  if(!regalloc_dry_run)
    {
      emitLabelNoSpill (tlbl1->key + 100);
      emit2 ("dec a");
      emit2 ("jp NZ,!tlabel", tlbl->key + 100);
    }
  regalloc_dry_run_cost += 4;

  freeAsmop (left, NULL, ic);
  freeAsmop (result, NULL, ic);
}


/*-----------------------------------------------------------------*/
/* genUnpackBits - generates code for unpacking bits               */
/*-----------------------------------------------------------------*/
static void
genUnpackBits (operand * result, int pair)
{
  int offset = 0;       /* result byte offset */
  int rsize;            /* result size */
  int rlen = 0;         /* remaining bit-field length */
  sym_link *etype;      /* bit-field type information */
  int blen;             /* bit-field length */
  int bstr;             /* bit-field starting bit within byte */

  emitDebug ("; genUnpackBits");

  etype = getSpec (operandType (result));
  rsize = getSize (operandType (result));
  blen = SPEC_BLEN (etype);
  bstr = SPEC_BSTR (etype);

  /* If the bit-field length is less than a byte */
  if (blen < 8)
    {
      emit2 ("ld a,!*pair", _pairs[pair].name);
      regalloc_dry_run_cost += (pair == PAIR_IX || pair == PAIR_IY) ? 3 : 1;
      AccRol (8 - bstr);
      emit2 ("and a,!immedbyte", ((unsigned char) -1) >> (8 - blen));
      regalloc_dry_run_cost += 2;
      if (!SPEC_USIGN (etype))
        {
          /* signed bit-field */
          if(!regalloc_dry_run)
            {
              symbol *tlbl = newiTempLabel (NULL);
              emit2 ("bit %d,a", blen - 1);
              emit2 ("jp Z,!tlabel", tlbl->key + 100);
              emit2 ("or a,!immedbyte", (unsigned char) (0xff << blen));
              emitLabelNoSpill (tlbl->key + 100);
            }
          regalloc_dry_run_cost += 7;
        }
      cheapMove (AOP (result), offset++, ASMOP_A, 0);
      goto finish;
    }

  /* TODO: what if pair == PAIR_DE ? */
  if (getPairId (AOP (result)) == PAIR_HL ||
    AOP_TYPE (result) == AOP_REG && rsize >= 2 && (AOP (result)->aopu.aop_reg[0]->rIdx == L_IDX || AOP (result)->aopu.aop_reg[0]->rIdx == H_IDX))
    {
      wassertl (rsize == 2, "HL must be of size 2");
      emit2 ("ld a,!*hl");
      emit2 ("inc hl");
      if(AOP_TYPE (result) != AOP_REG || AOP (result)->aopu.aop_reg[0]->rIdx != H_IDX)
        {
          emit2 ("ld h,!*hl");
          cheapMove (AOP (result), offset++, ASMOP_A, 0);
          emit2 ("ld a,h");
        }
      else
        {
          emit2 ("ld l,!*hl");
          cheapMove (AOP (result), offset++, ASMOP_A, 0);
          emit2 ("ld a,l");
        }
      emit2 ("and a,!immedbyte", ((unsigned char) -1) >> (16 - blen));
      regalloc_dry_run_cost += 7;
      if (!SPEC_USIGN (etype))
        {
          /* signed bit-field */
          if(!regalloc_dry_run)
            {
              symbol *tlbl = newiTempLabel (NULL);
              emit2 ("bit %d,a", blen - 1 - 8);
              emit2 ("jp Z,!tlabel", tlbl->key + 100);
              emit2 ("or a,!immedbyte", (unsigned char) (0xff << (blen - 8)));
              emitLabelNoSpill (tlbl->key + 100);
            }
          regalloc_dry_run_cost += 7;
        }
      cheapMove (AOP (result), offset++, ASMOP_A, 0);
      regalloc_dry_run_cost += 1;
      spillPair (PAIR_HL);
      return;
    }

  /* Bit field did not fit in a byte. Copy all
     but the partial byte at the end.  */
  for (rlen=blen;rlen>=8;rlen-=8)
    {
      emit2 ("ld a,!*pair", _pairs[pair].name);
      regalloc_dry_run_cost += 1;
      cheapMove (AOP (result), offset++, ASMOP_A, 0);
      if (rlen>8)
        {
          emit2 ("inc %s", _pairs[pair].name);
          regalloc_dry_run_cost += 1;
          _G.pairs[pair].offset++;
        }
    }

  /* Handle the partial byte at the end */
  if (rlen)
    {
      emit2 ("ld a,!*pair", _pairs[pair].name);
      emit2 ("and a,!immedbyte", ((unsigned char) -1) >> (8 - rlen));
      regalloc_dry_run_cost += 3;
      if (!SPEC_USIGN (etype))
        {
          /* signed bit-field */
          if(!regalloc_dry_run)
            {
              symbol *tlbl = newiTempLabel (NULL);
              emit2 ("bit %d,a", rlen - 1);
              emit2 ("jp Z,!tlabel", tlbl->key + 100);
              emit2 ("or a,!immedbyte", (unsigned char) (0xff << rlen));
              emitLabelNoSpill (tlbl->key + 100);
            }
          regalloc_dry_run_cost += 7;
        }
      cheapMove (AOP (result), offset++, ASMOP_A, 0);
    }

finish:
  if (offset < rsize)
    {
      asmop *source;

      if (SPEC_USIGN (etype))
        source = ASMOP_ZERO;
      else
        {
          /* signed bit-field: sign extension with 0x00 or 0xff */
          emit3 (A_RLA, 0, 0);
          emit3 (A_SBC, ASMOP_A, ASMOP_A);
          source = ASMOP_A;
        }
      rsize -= offset;
      while (rsize--)
        cheapMove (AOP (result), offset++, source, 0);
    }
}

static void
_moveFrom_tpair_(asmop *aop, int offset, PAIR_ID pair)
{
  if (!IS_GB && aop->type == AOP_REG)
    {
      if(!regalloc_dry_run)
        aopPut (aop, "!*hl", offset);
      regalloc_dry_run_cost += ld_cost (aop, ASMOP_A);
    }
  else
    {
      emit2 ("ld a,!*pair", _pairs[pair].name);
      regalloc_dry_run_cost += 1;
      cheapMove (aop, offset, ASMOP_A, 0);
    }
}

/*-----------------------------------------------------------------*/
/* genPointerGet - generate code for pointer get                   */
/*-----------------------------------------------------------------*/
static void
genPointerGet (const iCode *ic)
{
  operand *left, *result;
  int size, offset;
  int pair = PAIR_HL;
  sym_link *retype;

  left = IC_LEFT (ic);
  result = IC_RESULT (ic);
  retype = getSpec (operandType (result));

  if (IS_GB)
    pair = PAIR_DE;

  aopOp (left, ic, FALSE, FALSE);
  aopOp (result, ic, FALSE, FALSE);

  size = AOP_SIZE (result);

  if (isPair (AOP (left)) && size == 1 && !IS_BITVAR (retype))
    {
      /* Just do it */
      if (isPtrPair (AOP (left)))
        {
          if(!regalloc_dry_run) // Todo: More exact cost.
            {
              struct dbuf_s dbuf;

              dbuf_init (&dbuf, 128);
              dbuf_tprintf (&dbuf, "!*pair", getPairName (AOP (left)));
              aopPut (AOP (result), dbuf_c_str (&dbuf), 0);
              dbuf_destroy (&dbuf);
            }
          regalloc_dry_run_cost += ld_cost (AOP (result), ASMOP_A);
        }
      else
        {
          emit2 ("ld a,!*pair", getPairName (AOP (left)));
          regalloc_dry_run_cost += (getPairId (AOP (left)) == PAIR_IY ? 3 : 1);
          cheapMove (AOP (result), 0, ASMOP_A, 0);
        }

      goto release;
    }

  if (getPairId (AOP (left)) == PAIR_IY && !IS_BITVAR (retype))
    {
      if (IS_R2K && getPairId (AOP (result)) == PAIR_HL)
        {
          emit2 ("ld hl, (iy)");
          regalloc_dry_run_cost += 3;
          goto release;
        }

      /* Just do it */
      offset = 0;
      while (size--)
        {
          if (!regalloc_dry_run)
            {
              struct dbuf_s dbuf;

              dbuf_init (&dbuf, 128);
              dbuf_tprintf (&dbuf, "!*iyx", offset);
              aopPut (AOP (result), dbuf_c_str (&dbuf), offset);
              dbuf_destroy (&dbuf);
            }
          regalloc_dry_run_cost += ld_cost (AOP (result), ASMOP_A) + 2;	// Todo: More exact cost.
          offset++;
        }

      goto release;
    }

  /* For now we always load into temp pair */
  /* if this is rematerializable */
  if(!IS_GB && (getPairId (AOP (left)) == PAIR_BC || getPairId (AOP (left)) == PAIR_DE) && AOP_TYPE (result) == AOP_STK || getPairId (AOP (left)) == PAIR_IY && SPEC_BLEN (getSpec (operandType (result))) < 8)
    pair = getPairId (AOP (left));
  else
    fetchPair (pair, AOP (left));

  /* if bit then unpack */
  if (IS_BITVAR (retype))
    {
      genUnpackBits (result, pair);
      goto release;
    }
  else if (getPairId (AOP (result)) == PAIR_HL || size == 2 && AOP_TYPE (result) == AOP_REG && (AOP (result)->aopu.aop_reg[0] == regsZ80 + L_IDX || AOP (result)->aopu.aop_reg[0] == regsZ80 + H_IDX))
    {
       wassertl (size == 2, "HL must be of size 2");
      if (IS_R2K && getPairId (AOP (result)) == PAIR_HL)
        {
          emit2 ("ld hl, (hl)");
          regalloc_dry_run_cost += 3;
        }
      else
        {
          emit2 ("ld a,!*hl");
          emit2 ("inc hl");
          if(!regalloc_dry_run)
            aopPut (AOP (result), "!*hl", 1);
          regalloc_dry_run_cost += 3;
          cheapMove (AOP (result), 0, ASMOP_A, 0);
        }
      spillPair (PAIR_HL);
    }
  else if (pair == PAIR_HL || (!IS_GB && (getPairId (AOP (left)) == PAIR_BC || getPairId (AOP (left)) == PAIR_DE) && AOP_TYPE (result) == AOP_STK))
    {
      size = AOP_SIZE (result);
      offset = 0;

      if (size >= 2 && pair == PAIR_HL && AOP_TYPE (result) == AOP_REG)
        {
          int i, l = -10, h = -10, r;
          for (i = 0; i < size; i++)
            {
              if (AOP (result)->aopu.aop_reg[i]->rIdx == L_IDX)
                l = i;
              else if (AOP (result)->aopu.aop_reg[i]->rIdx == H_IDX)
                h = i;
            }

          if (l == -10 && h >= 0 && h < size - 1 || h == -10 && l >= 0 && l < size - 1)	// One byte of result somewehere in hl. Just assign it last.
            {
              r = (l == -10 ? h : l);

              while (size--)
                {
                  if (offset != r)
                    _moveFrom_tpair_ (AOP (result), offset, pair);

                  if (size)
                   {
                     offset++;
                     emit2 ("inc %s", _pairs[pair].name);
                     regalloc_dry_run_cost += 1;
                     _G.pairs[pair].offset++;
                   }
                }

              for (size = offset; size != r; size--)
                {
                  emit2 ("dec %s", _pairs[pair].name);
                  regalloc_dry_run_cost += 1;
                }

              _moveFrom_tpair_ (AOP (result), r, pair);

              // No fixup since result uses HL.

              goto release;
            }
          else if (l >= 0 && h >= 0 ) // Two bytes of result somewehere in hl. Assign it last and use a for caching.
            {
              while (size--)
                {
                  if (offset != l && offset != h)
                    _moveFrom_tpair_ (AOP (result), offset, pair);

                  if (size)
                   {
                     offset++;
                     emit2 ("inc %s", _pairs[pair].name);
                     regalloc_dry_run_cost += 1;
                     _G.pairs[pair].offset++;
                   }
                }

              r = (l > h ? l : h);
              for (size = offset; size != r; size--)
                {
                  emit2 ("dec %s", _pairs[pair].name);
                  regalloc_dry_run_cost += 1;
                }
              _moveFrom_tpair_ (ASMOP_A, 0, pair);

              r = (l < h ? l : h);
              for (; size != r; size--)
                {
                  emit2 ("dec %s", _pairs[pair].name);
                  regalloc_dry_run_cost += 1;
                }
              _moveFrom_tpair_ (AOP (result), r, pair);

              r = (l > h ? l : h);
              cheapMove (AOP (result), r, ASMOP_A, 0);

              // No fixup since result uses HL.

              goto release;
            }
        }

      while (size--)
        {
          _moveFrom_tpair_ (AOP (result), offset++, pair);

          if (size)
            {
              emit2 ("inc %s", _pairs[pair].name);
              regalloc_dry_run_cost += 1;
              _G.pairs[pair].offset++;
            }
        }
      /* Fixup HL back down */
      if (getPairId (AOP (left)) == pair && !isPairDead (pair, ic))
        for (size = AOP_SIZE (result)-1; size; size--)
          {
            emit2 ("dec %s", _pairs[pair].name);
            regalloc_dry_run_cost += 1;
            _G.pairs[pair].offset--;
          }
    }
  else
    {
      size = AOP_SIZE (result);
      offset = 0;

      while (size--)
        {
          /* PENDING: make this better */
          if (!IS_GB &&
              (AOP_TYPE (result) == AOP_REG || AOP_TYPE (result) == AOP_HLREG))
            {
              if(!regalloc_dry_run)
                aopPut (AOP (result), "!*hl", offset++);
              regalloc_dry_run_cost += ld_cost (AOP (result), ASMOP_A);
            }
          else
            {
              emit2 ("ld a,!*pair", _pairs[pair].name);
              regalloc_dry_run_cost += 1;
              cheapMove (AOP (result), offset++, ASMOP_A, 0);
            }
          if (size)
            {
              emit2 ("inc %s", _pairs[pair].name);
              regalloc_dry_run_cost += 1;
              _G.pairs[pair].offset++;
            }
        }
    }

release:
  freeAsmop (left, NULL, ic);
  freeAsmop (result, NULL, ic);
}

static bool
isRegOrLit (asmop * aop)
{
  if (aop->type == AOP_REG || aop->type == AOP_LIT || aop->type == AOP_IMMD || aop->type == AOP_HLREG)
    return TRUE;
  return FALSE;
}


/*-----------------------------------------------------------------*/
/* genPackBits - generates code for packed bit storage             */
/*-----------------------------------------------------------------*/
static void
genPackBits (sym_link * etype,
             operand * right,
             int pair,
             const iCode *ic)
{
  int offset = 0;       /* source byte offset */
  int pair_offset = 0;
  int rlen = 0;         /* remaining bit-field length */
  int blen;             /* bit-field length */
  int bstr;             /* bit-field starting bit within byte */
  int litval;           /* source literal value (if AOP_LIT) */
  unsigned char mask;   /* bitmask within current byte */
  int extraPair;        /* a tempory register */
  bool needPopExtra=0;  /* need to restore original value of temp reg */

  emitDebug ("; genPackBits","");

  blen = SPEC_BLEN (etype);
  bstr = SPEC_BSTR (etype);

  /* If the bit-field length is less than a byte */
  if (blen < 8)
    {
      mask = ((unsigned char) (0xFF << (blen + bstr)) |
              (unsigned char) (0xFF >> (8 - bstr)));

      if (AOP_TYPE (right) == AOP_LIT)
        {
          /* Case with a bit-field length <8 and literal source */
          litval = (int) ulFromVal (AOP (right)->aopu.aop_lit);
          litval <<= bstr;
          litval &= (~mask) & 0xff;
          emit2 ("ld a,!*pair", _pairs[pair].name);
          regalloc_dry_run_cost += (pair == PAIR_IX || pair == PAIR_IY) ? 3 : 1;
          if ((mask|litval)!=0xff)
            {
              emit2 ("and a,!immedbyte", mask);
              regalloc_dry_run_cost += 2;
            }
          if (litval)
            {
              emit2 ("or a,!immedbyte", litval);
              regalloc_dry_run_cost += 1;
            }
          emit2 ("ld !*pair,a", _pairs[pair].name);
          regalloc_dry_run_cost += (pair == PAIR_IX || pair == PAIR_IY) ? 3 : 1;
          return;
        }
      else
        {
          /* Case with a bit-field length <8 and arbitrary source */
          cheapMove (ASMOP_A, 0, AOP (right), 0);
          /* shift and mask source value */
          AccLsh (bstr);
          emit2 ("and a,!immedbyte", (~mask) & 0xff);
          regalloc_dry_run_cost += 2;

          extraPair = getFreePairId(ic);
          if (extraPair == PAIR_INVALID)
            {
              if (pair != PAIR_HL)
                extraPair = PAIR_HL;
              else
                {
                  extraPair = PAIR_BC;
                  if (getPairId (AOP (right)) != PAIR_BC || !isLastUse (ic, right))
                    {
                      _push (extraPair);
                      needPopExtra = 1;
                    }
                }
            }
          emit2 ("ld %s,a", _pairs[extraPair].l);
          regalloc_dry_run_cost += 1;
          emit2 ("ld a,!*pair", _pairs[pair].name);
          regalloc_dry_run_cost += (pair == PAIR_IX || pair == PAIR_IY) ? 3 : 1;

          emit2 ("and a,!immedbyte", mask);
          regalloc_dry_run_cost += 2;
          emit2 ("or a,%s", _pairs[extraPair].l);
          regalloc_dry_run_cost += 1;
          emit2 ("ld !*pair,a", _pairs[pair].name);
          regalloc_dry_run_cost += (pair == PAIR_IX || pair == PAIR_IY) ? 3 : 1;
          if (needPopExtra)
            _pop (extraPair);
          return;
        }
    }

  /* Bit length is greater than 7 bits. In this case, copy  */
  /* all except the partial byte at the end                 */
  for (rlen=blen;rlen>=8;rlen-=8)
    {
      cheapMove (ASMOP_A, 0, AOP (right), offset++);
      if (pair == PAIR_IX || pair == PAIR_IY)
        {
          emit2 ("ld %d !*pair,a", pair_offset, _pairs[pair].name);
          regalloc_dry_run_cost += 3;
        }
      else
        {
          emit2 ("ld !*pair,a", _pairs[pair].name);
          regalloc_dry_run_cost += 1;
        }
      if (rlen > 8 && pair != PAIR_IX && pair != PAIR_IY)
        {
          emit2 ("inc %s", _pairs[pair].name);
          regalloc_dry_run_cost += 1;
          _G.pairs[pair].offset++;
        }
      else
        pair_offset++;
    }

  /* If there was a partial byte at the end */
  if (rlen)
    {
      mask = (((unsigned char) -1 << rlen) & 0xff);

      if (AOP_TYPE (right) == AOP_LIT)
        {
          /* Case with partial byte and literal source */
          litval = (int) ulFromVal (AOP (right)->aopu.aop_lit);
          litval >>= (blen-rlen);
          litval &= (~mask) & 0xff;
          
          if (pair == PAIR_IX || pair == PAIR_IY)
            {
              emit2 ("ld a, %d !*pair", pair_offset, _pairs[pair].name);
              regalloc_dry_run_cost += 3;
            }
          else
            {
              emit2 ("ld a, !*pair", _pairs[pair].name);
              regalloc_dry_run_cost += 1;
            }

          if ((mask|litval)!=0xff)
            emit2 ("and a,!immedbyte", mask);
          if (litval)
            emit2 ("or a,!immedbyte", litval);
        }
      else
        {
          /* Case with partial byte and arbitrary source */
          cheapMove (ASMOP_A, 0, AOP (right), offset++);
          emit2 ("and a,!immedbyte", (~mask) & 0xff);
          regalloc_dry_run_cost += 2;

          extraPair = getFreePairId(ic);
          if (extraPair == PAIR_INVALID)
            {
              if (pair != PAIR_HL)
                extraPair = PAIR_HL;
              else
                {
                  extraPair = PAIR_BC;
                  if (getPairId (AOP (right)) != PAIR_BC || !isLastUse (ic, right))
                    {
                      _push (extraPair);
                      needPopExtra = 1;
                    }
                }
            }
            
          emit2 ("ld %s,a", _pairs[extraPair].l);
          regalloc_dry_run_cost += 1;
          
          if (pair == PAIR_IX || pair == PAIR_IY)
            {
              emit2 ("ld a, %d !*pair", pair_offset, _pairs[pair].name);
              regalloc_dry_run_cost += 3;
            }
          else
            {
              emit2 ("ld a, !*pair", _pairs[pair].name);
              regalloc_dry_run_cost += 1;
            }

          emit2 ("and a,!immedbyte", mask);
          regalloc_dry_run_cost += 2;
          emit2 ("or a,%s", _pairs[extraPair].l);
          regalloc_dry_run_cost += 1;
          if (needPopExtra)
            _pop (extraPair);

        }
      if (pair == PAIR_IX || pair == PAIR_IY)
        {
          emit2 ("ld %d !*pair, a", pair_offset, _pairs[pair].name);
          regalloc_dry_run_cost += 3;
        }
      else
        {
          emit2 ("ld !*pair, a", _pairs[pair].name);
          regalloc_dry_run_cost += 1;
        }
    }
}

/*-----------------------------------------------------------------*/
/* genPointerSet - stores the value into a pointer location        */
/*-----------------------------------------------------------------*/
static void
genPointerSet (iCode * ic)
{
  int size, offset;
  operand *right, *result;
  PAIR_ID pairId = PAIR_HL;
  bool isBitvar;
  sym_link *retype; 
  sym_link *letype;
  
  right = IC_RIGHT (ic);
  result = IC_RESULT (ic);
  retype = getSpec (operandType (right));
  letype = getSpec (operandType (result));

  aopOp (result, ic, FALSE, FALSE);
  aopOp (right, ic, FALSE, FALSE);

  if (IS_GB)
    pairId = PAIR_DE;

  size = AOP_SIZE (right);

  isBitvar = IS_BITVAR(retype) || IS_BITVAR(letype);
  emitDebug("; isBitvar = %d", isBitvar);

  /* Handle the exceptions first */
  if (isPair (AOP (result)) && size == 1 && !isBitvar)
    {
      /* Just do it */
      const char *pair = getPairName (AOP (result));
      if (canAssignToPtr3 (AOP (right)) && isPtr (pair))	// Todo: correct cost for pair iy.
        {
          if(!regalloc_dry_run)
            emit2 ("ld !*pair,%s", pair, aopGet (AOP (right), 0, FALSE));
          regalloc_dry_run_cost += ld_cost(ASMOP_A, AOP (right)) + (getPairId (AOP (result)) != PAIR_IY ? 0 : 2);
        }
      else
        {
          cheapMove (ASMOP_A, 0, AOP (right), 0);
          emit2 ("ld !*pair,a", pair);
          regalloc_dry_run_cost += (getPairId (AOP (result)) != PAIR_IY ? 1 : 3);
        }
      goto release;
    }

  if ( getPairId( AOP (result)) == PAIR_IY && !isBitvar)
    {
      /* Just do it */
      offset = 0;
      while (size--)
        {
          if (canAssignToPtr3 (AOP (right)))
            {
              if(!regalloc_dry_run)
                emit2 ("ld !*iyx,%s", offset, aopGet( AOP(right), offset, FALSE));
              regalloc_dry_run_cost += 3; // Todo: More exact cost here!
            }
          else
            {
              cheapMove (ASMOP_A, 0, AOP (right), offset);
              emit2 ("ld !*iyx,a", offset);
              regalloc_dry_run_cost += 3;
            }
          offset++;
        }
      goto release;
    }
  else if (getPairId (AOP (result)) == PAIR_HL && !isLastUse (ic, result)
           && !isBitvar)
    {
      offset = 0;

      while (size--)
        {
          if (isRegOrLit (AOP (right)) && !IS_GB)
            {
              if(!regalloc_dry_run)
                emit2 ("ld !*pair,%s", _pairs[PAIR_HL].name, aopGet (AOP (right), offset, FALSE));
              regalloc_dry_run_cost += ld_cost(ASMOP_A, AOP (right));
            }
          else
            {
              cheapMove (ASMOP_A, 0, AOP (right), offset);
              emit2 ("ld !*pair,a", _pairs[PAIR_HL].name);
              regalloc_dry_run_cost += 1;
            }
          if (size)
            {
              emit2 ("inc %s", _pairs[PAIR_HL].name);
              regalloc_dry_run_cost += 1;
              _G.pairs[PAIR_HL].offset++;
            }
          offset++;
        }

      /* Fixup HL back down */
      for (size = AOP_SIZE (right)-1; size; size--)
        {
          emit2 ("dec %s", _pairs[PAIR_HL].name);
          regalloc_dry_run_cost += 1;
        }
      goto release;
    }

  /* if the operand is already in dptr
     then we do nothing else we move the value to dptr */
  if (AOP_TYPE (result) != AOP_STR)
    {
      if (isBitvar && getPairId( AOP (result)) != PAIR_INVALID &&
        (getPairId( AOP (result)) != PAIR_IY || SPEC_BLEN (IS_BITVAR (retype) ? retype : letype) < 8 || isLastUse (ic, result))) /* Avoid destroying result by increments */
        pairId = getPairId( AOP (result));
      else
        fetchPair (pairId, AOP (result));
    }
  /* so hl now contains the address */
  freeAsmop (result, NULL, ic);

  /* if bit then unpack */
  if (isBitvar)
    {
      genPackBits ((IS_BITVAR (retype) ? retype : letype), right, pairId, ic);
      goto release;
    }
  else
    {
      offset = 0;

      while (size--)
        {
          if (isRegOrLit (AOP (right)) && !IS_GB)
            {
              if(!regalloc_dry_run)
                emit2 ("ld !*pair,%s", _pairs[pairId].name, aopGet (AOP (right), offset, FALSE));
              regalloc_dry_run_cost += ld_cost(ASMOP_A, AOP (right));
            }
          else
            {
              cheapMove (ASMOP_A, 0, AOP (right), offset);
              emit2 ("ld !*pair,a", _pairs[pairId].name);
              regalloc_dry_run_cost += 1;
            }
          if (size)
            {
              emit2 ("inc %s", _pairs[pairId].name);
              regalloc_dry_run_cost += 1;
              _G.pairs[pairId].offset++;
            }
          offset++;
        }
    }
release:
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genIfx - generate code for Ifx statement                        */
/*-----------------------------------------------------------------*/
static void
genIfx (iCode * ic, iCode * popIc)
{
  operand *cond = IC_COND (ic);
  int isbit = 0;

  aopOp (cond, ic, FALSE, TRUE);

  /* get the value into acc */
  if(AOP_TYPE (cond) != AOP_CRY &&
    !IS_BOOL (operandType(cond)))
    _toBoolean (cond, FALSE);
  /* Special case: Condition is bool */
  else if(IS_BOOL (operandType(cond)))
    {
      if(!regalloc_dry_run)
        {
          emit2 ("bit 0,%s", aopGet (AOP (cond), 0, FALSE));
          emit2 ("jp %s,!tlabel", IC_TRUE (ic) ? "NZ" : "Z",
            (IC_TRUE (ic) ? IC_TRUE (ic) : IC_FALSE (ic))->key + 100);
        }
      regalloc_dry_run_cost += (bit8_cost(AOP (cond)) + 3);
      
      freeAsmop (cond, NULL, ic);
      if (!regalloc_dry_run)
        ic->generated = 1;
      return;
    }
  else
    isbit = 1;
  /* the result is now in the accumulator */
  freeAsmop (cond, NULL, ic);

  /* if there was something to be popped then do it */
  if (popIc)
    genIpop (popIc);

  /* if the condition is  a bit variable */
  if (isbit && IS_ITEMP (cond) &&
      SPIL_LOC (cond))
    genIfxJump (ic, SPIL_LOC (cond)->rname);
  else if (isbit && !IS_ITEMP (cond))
    genIfxJump (ic, OP_SYMBOL (cond)->rname);
  else
    genIfxJump (ic, "a");

  if (!regalloc_dry_run)
    ic->generated = 1;
}

/*-----------------------------------------------------------------*/
/* genAddrOf - generates code for address of                       */
/*-----------------------------------------------------------------*/
static void
genAddrOf (const iCode *ic)
{
  symbol *sym = OP_SYMBOL (IC_LEFT (ic));

  aopOp (IC_RESULT (ic), ic, FALSE, FALSE);

  /* if the operand is on the stack then we
     need to get the stack offset of this
     variable */
  if (IS_GB)
    {
      if (sym->onStack)
        {
          spillPair (PAIR_HL);
          if (sym->stack <= 0)
            {
              setupPairFromSP (PAIR_HL, sym->stack + _G.stack.pushed + _G.stack.offset);
            }
          else
            {
              setupPairFromSP (PAIR_HL, sym->stack + _G.stack.pushed + _G.stack.offset + _G.stack.param_offset);
            }
          commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
        }
      else
        {
          emit2 ("ld de,!hashedstr", sym->rname);
          regalloc_dry_run_cost += 3;
          commitPair (AOP (IC_RESULT (ic)), PAIR_DE);
        }
    }
  else
    {
      spillPair (PAIR_HL);
      if (sym->onStack)
        {
          /* if it has an offset  then we need to compute it */
          if (sym->stack > 0)
            emit2 ("ld hl,!immedword", sym->stack + _G.stack.pushed + _G.stack.offset + _G.stack.param_offset);
          else
            emit2 ("ld hl,!immedword", sym->stack + _G.stack.pushed + _G.stack.offset);
          regalloc_dry_run_cost += 3;
          emit2 ("add hl,sp");
          regalloc_dry_run_cost += 1;
        }
      else
        {
          emit2 ("ld hl,!hashedstr", sym->rname);
          regalloc_dry_run_cost += 3;
        }
      commitPair (AOP (IC_RESULT (ic)), PAIR_HL);
    }
  freeAsmop (IC_RESULT (ic), NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genAssign - generate code for assignment                        */
/*-----------------------------------------------------------------*/
static void
genAssign (const iCode *ic)
{
  operand *result, *right;
  int size, offset;
  unsigned long lit = 0L;

  result = IC_RESULT (ic);
  right = IC_RIGHT (ic);

  /* Dont bother assigning if they are the same */
  if (operandsEqu (IC_RESULT (ic), IC_RIGHT (ic)))
    return;

  aopOp (right, ic, FALSE, FALSE);
  aopOp (result, ic, TRUE, FALSE);

  /* if they are the same registers */
  if (sameRegs (AOP (right), AOP (result)))
    {
      emitDebug ("; (registers are the same)");
      goto release;
    }

  /* if the result is a bit */
  if (AOP_TYPE (result) == AOP_CRY)
    {
      wassertl (0, "Tried to assign to a bit");
    }

  /* general case */
  size = AOP_SIZE (result);
  offset = 0;

  if (AOP_TYPE (right) == AOP_LIT)
    {
      lit = ulFromVal (AOP (right)->aopu.aop_lit);
    }

  if (isPair (AOP (result)))
    {
      fetchPairLong (getPairId (AOP (result)), AOP (right), ic, LSB);
    }
  else if (getPairId (AOP (right)) == PAIR_IY)
    {
      while (size--)
        {
          if(size == 0)
            {
              emit2 ("push iy");
              emit2 ("dec sp");
              emit2 ("pop af");
              emit2 ("inc sp");
              regalloc_dry_run_cost += 5;
              cheapMove (AOP (result), size, ASMOP_A , 0);
            }
          else if(size == 1)
            {
              emit2 ("push iy");
              emit2 ("pop af");
              regalloc_dry_run_cost += 3;
              cheapMove (AOP (result), size, ASMOP_A , 0);
            }
          else
            cheapMove (AOP (result), size, ASMOP_ZERO, 0);
        }
    }
  else if ((size > 1) &&
           (AOP_TYPE (result) != AOP_REG) &&
           (AOP_TYPE (right) == AOP_LIT) &&
           !IS_FLOAT (operandType (right)) &&
           (lit < 256L))
    {
      bool fXored = FALSE;
      offset = 0;
      /* Work from the top down.
         Done this way so that we can use the cached copy of 0
         in A for a fast clear */
      while (size--)
        {
          if ((unsigned int) ((lit >> (offset * 8)) & 0x0FFL) == 0)
            {
              if (!fXored && size > 1)
                {
                  emit3 (A_XOR, ASMOP_A, ASMOP_A);
                  fXored = TRUE;
                }
              cheapMove (AOP (result), offset, fXored ? ASMOP_A : ASMOP_ZERO, 0);
            }
          else
            cheapMove (AOP (result), offset, AOP (right), offset);
          offset++;
        }
    }
  else if (size == 2 && requiresHL (AOP (right)) && requiresHL (AOP (result)) && (IS_GB /*|| IY_RESERVED*/))
    {
      /* Special case.  Load into a and d, then load out. */
      cheapMove (ASMOP_A, 0, AOP (right), 0);
      emit3_o (A_LD, ASMOP_E, 0, AOP (right), 1);
      cheapMove (AOP (result), 0, ASMOP_A, 0);
      cheapMove (AOP (result), 1, ASMOP_E, 0);
    }
  else if (size == 4 && requiresHL (AOP (right)) && requiresHL (AOP (result)) && (IS_GB /*|| IY_RESERVED*/))
    {
      /* Special case - simple memcpy */
      if (!regalloc_dry_run)
        {
          aopGet (AOP (right), LSB, FALSE);
          emit2 ("ld d,h");
          emit2 ("ld e,l");
          aopGet (AOP (result), LSB, FALSE);
        }
      regalloc_dry_run_cost += 8;	// Todo: More exact cost here!

      while (size--)
        {
          emit2 ("ld a,(de)");
          /* Peephole will optimise this. */
          emit2 ("ld (hl),a");
          regalloc_dry_run_cost += 2;
          if (size != 0)
            {
              emit2 ("inc hl");
              emit2 ("inc de");
              regalloc_dry_run_cost += 2;
            }
        }
      spillPair (PAIR_HL);
    }
  else
    {
      if (AOP_TYPE (result) == AOP_REG && AOP_TYPE (right) == AOP_REG)
        {
          // We need to be able to handle any assignment here, ensuring not to overwrite any parts of the source that we still need.
        
          bool assigned[8] = {FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE};	// This has to be made bigger when sdcc supports variables larger than 8 bytes in registers.
          int cached_byte = -1;

          while (size--)
            {
              int i;
              
              // Find lowest byte that can be assigned and needs to be assigned.
              for (i = 0; i < AOP_SIZE (result); i++)
                {
                  int j;
                  
                  if (assigned[i])
                    continue;
                    
                  for (j = 0; j < (AOP_SIZE (result) < AOP_SIZE (right) ? AOP_SIZE (result) : AOP_SIZE (right)); j++)
                    {
                      if (!assigned[j] && i != j && AOP (result)->aopu.aop_reg[i]->rIdx == AOP (right)->aopu.aop_reg[j]->rIdx)
                        goto skip_byte; // We can't write this one without overwriting the source.
                    }
                  
                  break; // Found byte that can be written safely.
                  
                  skip_byte:;
                }

              if (i < AOP_SIZE (result))
                {
                  cheapMove (AOP (result), i, AOP(right), i); // We can safely assign a byte.
                  assigned[i] = TRUE;
                  continue;
                }
              
              // No byte can be assigned safely (i.e. the assignment is a permutation). Cache one in the accumulator.
 
              if (cached_byte != -1)
                {
                  // Already one cached. Can happen when the assignment is a permutation consisting of multiple cycles.
                  cheapMove (AOP (result), cached_byte, ASMOP_A, 0);
                  cached_byte = -1;
                  continue;
                }
              
              for (i = 0; i < AOP_SIZE (result); i++)
                if (!assigned[i])
                  break;
              wassertl (i != AOP_SIZE (result), "genAssign error: Trying to cache non-existant byte in accumulator."); 
              cheapMove (ASMOP_A, 0, AOP (right), i);
              assigned[i] = TRUE;
              cached_byte = i;
            }
           
          if (cached_byte != -1)
            cheapMove (AOP (result), cached_byte, ASMOP_A, 0);
        }
      else
        while (size--)
          {
            /* PENDING: do this check better */
            if ((IS_GB || IY_RESERVED) && requiresHL (AOP (right)) && requiresHL (AOP (result)))
              {
                _push (PAIR_HL);
                cheapMove (ASMOP_A, 0, AOP (right), offset);
                cheapMove (AOP (result), offset, ASMOP_A, 0);
                _pop (PAIR_HL);
                spillPair (PAIR_HL);
              }
            else
              cheapMove (AOP (result), offset, AOP (right), offset);
            offset++;
          }
    }

release:
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genJumpTab - genrates code for jump table                       */
/*-----------------------------------------------------------------*/
static void
genJumpTab (const iCode *ic)
{
  symbol *jtab = NULL;

  aopOp (IC_JTCOND (ic), ic, FALSE, FALSE);
  /* get the condition into accumulator */
  if (!IS_GB && !isPairDead(PAIR_DE, ic))
    _push (PAIR_DE);
  cheapMove (ASMOP_E, 0, AOP (IC_JTCOND (ic)), 0);
  if(!regalloc_dry_run)
    {
      emit2 ("ld d,!zero");
      jtab = newiTempLabel (NULL);
    }
  regalloc_dry_run_cost += 2;
  spillPair (PAIR_HL);
  if(!regalloc_dry_run)
    {
      emit2 ("ld hl,!immed!tlabel", jtab->key + 100);
      emit2 ("add hl,de");
      emit2 ("add hl,de");
      emit2 ("add hl,de");
    }
  regalloc_dry_run_cost += 5;
  freeAsmop (IC_JTCOND (ic), NULL, ic);
  if (!IS_GB && !isPairDead(PAIR_DE, ic))
    _pop (PAIR_DE);
  if(!regalloc_dry_run)
    {
      emit2 ("jp !*hl");
      emitLabel (jtab->key + 100);
    }
  regalloc_dry_run_cost += 1;
  /* now generate the jump labels */
  for (jtab = setFirstItem (IC_JTLABELS (ic)); jtab;
       jtab = setNextItem (IC_JTLABELS (ic)))
    if(!regalloc_dry_run)
      emit2 ("jp !tlabel", jtab->key + 100);
    /*regalloc_dry_run_cost += 3 doesn't matter and might overflow cost*/
}

/*-----------------------------------------------------------------*/
/* genCast - gen code for casting                                  */
/*-----------------------------------------------------------------*/
static void
genCast (const iCode *ic)
{
  operand *result = IC_RESULT (ic);
  sym_link *rtype = operandType (IC_RIGHT (ic));
  operand *right = IC_RIGHT (ic);
  int size, offset;

  /* if they are equivalent then do nothing */
  if (operandsEqu (IC_RESULT (ic), IC_RIGHT (ic)))
    return;

  aopOp (right, ic, FALSE, FALSE);
  aopOp (result, ic, FALSE, FALSE);

  /* if the result is a bit */
  if (AOP_TYPE (result) == AOP_CRY)
    {
      wassertl (0, "Tried to cast to a bit");
    }

  /* casting to bool */
  if (IS_BOOL(operandType(result)))
    {
      _castBoolean (right);
      outAcc (result);
      goto release;
    }

  /* if they are the same size : or less */
  if (AOP_SIZE (result) <= AOP_SIZE (right))
    {
      genAssign (ic);
      goto release;
    }

  /* So we now know that the size of destination is greater
     than the size of the source */
  /* we move to result for the size of source */
  size = AOP_SIZE (right);
  offset = 0;
  while (size--)
    {
      cheapMove (AOP (result), offset, AOP (right), offset);
      offset++;
    }

  /* now depending on the sign of the destination */
  size = AOP_SIZE (result) - AOP_SIZE (right);
  /* Unsigned or not an integral type - right fill with zeros */
  if (!IS_SPEC (rtype) || SPEC_USIGN (rtype) || AOP_TYPE(right)==AOP_CRY)
    {
      while (size--)
        aopPut3 (AOP (result), offset++, ASMOP_ZERO, 0);
    }
  else
    {
      /* we need to extend the sign :{ */
      cheapMove (ASMOP_A, 0, AOP (right), AOP_SIZE (right) - 1);
      emit3 (A_RLA, 0, 0);
      emit3 (A_SBC, ASMOP_A, ASMOP_A);
      while (size--)
        cheapMove (AOP (result), offset++, ASMOP_A, 0);
    }

release:
  freeAsmop (right, NULL, ic);
  freeAsmop (result, NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genReceive - generate code for a receive iCode                  */
/*-----------------------------------------------------------------*/
static void
genReceive (const iCode *ic)
{
  wassert(!regalloc_dry_run);

  if (isOperandInFarSpace (IC_RESULT (ic)) &&
      (OP_SYMBOL (IC_RESULT (ic))->isspilt ||
       IS_TRUE_SYMOP (IC_RESULT (ic))))
    {
      wassert (0);
    }
  else
    {
        // PENDING: HACK
        int size;
        int i;

        aopOp (IC_RESULT (ic), ic, FALSE, FALSE);
        size = AOP_SIZE(IC_RESULT(ic));

        for (i = 0; i < size; i++) {
            aopPut(AOP(IC_RESULT(ic)), _fReceive[_G.receiveOffset++], i);
        }
    }

  freeAsmop (IC_RESULT (ic), NULL, ic);
}

/*-----------------------------------------------------------------*/
/* genDummyRead - generate code for dummy read of volatiles        */
/*-----------------------------------------------------------------*/
static void
genDummyRead (const iCode *ic)
{
  operand *op;
  int size, offset;

  op = IC_RIGHT (ic);
  if (op && IS_SYMOP (op))
    {
      aopOp (op, ic, FALSE, FALSE);

      /* general case */
      size = AOP_SIZE (op);
      offset = 0;

      while (size--)
        {
          _moveA3 (AOP (op), offset);
          offset++;
        }

      freeAsmop (op, NULL, ic);
    }

  op = IC_LEFT (ic);
  if (op && IS_SYMOP (op))
    {
      aopOp (op, ic, FALSE, FALSE);

      /* general case */
      size = AOP_SIZE (op);
      offset = 0;

      while (size--)
        {
          _moveA3 (AOP (op), offset);
          offset++;
        }

      freeAsmop (op, NULL, ic);
    }
}

/*-----------------------------------------------------------------*/
/* genCritical - generate code for start of a critical sequence    */
/*-----------------------------------------------------------------*/
static void
genCritical (const iCode *ic)
{
  symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);

  if (IS_GB || IS_R2K)
    {
      emit2 ("!di");
      regalloc_dry_run_cost += 1;
    }
  else if (IC_RESULT (ic))
    {
      aopOp (IC_RESULT (ic), ic, TRUE, FALSE);
      aopPut3 (AOP (IC_RESULT (ic)), 0, ASMOP_ZERO, 0);
      if(!regalloc_dry_run)
        {
          //get interrupt enable flag IFF2 into P/O
          emit2 ("ld a,i");
	  
          //disable interrupt
          emit2 ("!di");
          //parity odd <==> P/O=0 <==> interrupt enable flag IFF2=0
          emit2 ("jp PO,!tlabel", tlbl->key + 100);
        }
      regalloc_dry_run_cost += 5;
      aopPut3 (AOP (IC_RESULT (ic)), 0, ASMOP_ONE, 0);
      if(!regalloc_dry_run_cost)
        {
          emit2 ("!tlabeldef", (tlbl->key + 100));
          _G.lines.current->isLabel = 1;
        }
      freeAsmop (IC_RESULT (ic), NULL, ic);
    }
  else
    {
      //get interrupt enable flag IFF2 into P/O
      emit2 ("ld a,i");
      
      //disable interrupt
      emit2 ("!di");
      regalloc_dry_run_cost += 2;
      //save P/O flag
      _push (PAIR_AF);
    }
}

/*-----------------------------------------------------------------*/
/* genEndCritical - generate code for end of a critical sequence   */
/*-----------------------------------------------------------------*/
static void
genEndCritical (const iCode *ic)
{
  symbol *tlbl = regalloc_dry_run ? 0 : newiTempLabel (0);

  if (IS_GB)
    {
      emit2 ("!ei");
      regalloc_dry_run_cost += 1;
    }
  else if (IS_R2K)
    {
      emit2 ("ipres");
      regalloc_dry_run_cost += 1;
    }
  else if (IC_RIGHT (ic))
    {
      aopOp (IC_RIGHT (ic), ic, FALSE, TRUE);
      _toBoolean (IC_RIGHT (ic), TRUE);
      
      if(!regalloc_dry_run)
        {
          //don't enable interrupts if they were off before
          emit2 ("jp Z,!tlabel", tlbl->key + 100);
          emit2 ("!ei");
          emitLabel (tlbl->key + 100);
        }
      regalloc_dry_run_cost += 4;
      freeAsmop (IC_RIGHT (ic), NULL, ic);
    }
  else
    {
      //restore P/O flag
      _pop (PAIR_AF);
      //parity odd <==> P/O=0 <==> interrupt enable flag IFF2 was 0 <==>
      //don't enable interrupts as they were off before
      if(!regalloc_dry_run)
        {
          emit2 ("jp PO,!tlabel", tlbl->key + 100);
          emit2 ("!ei");
          emit2 ("!tlabeldef", (tlbl->key + 100));
          _G.lines.current->isLabel = 1;
        }
      regalloc_dry_run_cost += 4;
    }
}

#if 0 //Disabled since it doesn't work for arrays of float.
enum
  {
    /** Maximum number of bytes to emit per line. */
    DBEMIT_MAX_RUN = 8
  };

/** Context for the byte output chunker. */
typedef struct
{
  unsigned char buffer[DBEMIT_MAX_RUN];
  int pos;
} DBEMITCTX;


/** Flushes a byte chunker by writing out all in the buffer and
    reseting.
*/
static void
_dbFlush(DBEMITCTX *self)
{
  char line[256];

  if (self->pos > 0)
    {
      int i;
      sprintf(line, ".db 0x%02X", self->buffer[0]);

      for (i = 1; i < self->pos; i++)
        {
          sprintf(line + strlen(line), ", 0x%02X", self->buffer[i]);
        }
      emit2(line);
    }
  self->pos = 0;
}

/** Write out another byte, buffering until a decent line is
    generated.
*/
static void
_dbEmit(DBEMITCTX *self, int c)
{
  if (self->pos == DBEMIT_MAX_RUN)
    {
      _dbFlush(self);
    }
  self->buffer[self->pos++] = c;
}

/** Context for a simple run length encoder. */
typedef struct
{
  unsigned last;
  unsigned char buffer[128];
  int pos;
  /** runLen may be equivalent to pos. */
  int runLen;
} RLECTX;

enum
  {
    RLE_CHANGE_COST = 4,
    RLE_MAX_BLOCK = 127
  };

/** Flush the buffer of a run length encoder by writing out the run or
    data that it currently contains.
*/
static void
_rleCommit(RLECTX *self)
{
  int i;
  if (self->pos != 0)
    {
      DBEMITCTX db;
      memset(&db, 0, sizeof(db));

      emit2(".db %u", self->pos);

      for (i = 0; i < self->pos; i++)
        {
          _dbEmit(&db, self->buffer[i]);
        }
      _dbFlush(&db);
    }
  /* Reset */
  self->pos = 0;
}

/* Encoder design:
   Can get either a run or a block of random stuff.
   Only want to change state if a good run comes in or a run ends.
   Detecting run end is easy.
   Initial state?

   Say initial state is in run, len zero, last zero.  Then if you get a
   few zeros then something else then a short run will be output.
   Seems OK.  While in run mode, keep counting.  While in random mode,
   keep a count of the run.  If run hits margin, output all up to run,
   restart, enter run mode.
*/

/** Add another byte into the run length encoder, flushing as
    required.  The run length encoder uses the Amiga IFF style, where
    a block is prefixed by its run length.  A positive length means
    the next n bytes pass straight through.  A negative length means
    that the next byte is repeated -n times.  A zero terminates the
    chunks.
*/
static void
_rleAppend(RLECTX *self, unsigned c)
{
  int i;

  if (c != self->last)
    {
      /* The run has stopped.  See if it is worthwhile writing it out
         as a run.  Note that the random data comes in as runs of
         length one.
      */
      if (self->runLen > RLE_CHANGE_COST)
        {
          /* Yes, worthwhile. */
          /* Commit whatever was in the buffer. */
          _rleCommit(self);
          emit2("!db !immed-%u,!immedbyte", self->runLen, self->last);
        }
      else
        {
          /* Not worthwhile.  Append to the end of the random list. */
          for (i = 0; i < self->runLen; i++)
            {
              if (self->pos >= RLE_MAX_BLOCK)
                {
                  /* Commit. */
                  _rleCommit(self);
                }
              self->buffer[self->pos++] = self->last;
            }
        }
      self->runLen = 1;
      self->last = c;
    }
  else
    {
      if (self->runLen >= RLE_MAX_BLOCK)
        {
          /* Commit whatever was in the buffer. */
          _rleCommit(self);

          emit2 ("!db !immed-%u,!immedbyte", self->runLen, self->last);
          self->runLen = 0;
        }
      self->runLen++;
    }
}

static void
_rleFlush(RLECTX *self)
{
  _rleAppend(self, -1);
  _rleCommit(self);
  self->pos = 0;
  self->last = 0;
  self->runLen = 0;
}

/** genArrayInit - Special code for initialising an array with constant
   data.
*/

static void
genArrayInit (iCode * ic)
{
  literalList *iLoop;
  int         ix;
  int         elementSize = 0, eIndex, i;
  unsigned    val, lastVal;
  sym_link    *type;
  RLECTX      rle;

  memset(&rle, 0, sizeof(rle));

  aopOp (IC_LEFT(ic), ic, FALSE, FALSE);

  _saveRegsForCall(ic, 0);

  fetchPair (PAIR_HL, AOP (IC_LEFT (ic)));
  emit2 ("call __initrleblock");

  type = operandType(IC_LEFT(ic));

  if (type && type->next)
    {
      if (IS_SPEC(type->next) || IS_PTR(type->next))
        {
          elementSize = getSize(type->next);
        }
      else if (IS_ARRAY(type->next) && type->next->next)
        {
          elementSize = getSize(type->next->next);
        }
      else
        {
          printTypeChainRaw (type, NULL);
          wassertl (0, "Can't determine element size in genArrayInit.");
        }
    }
  else
    {
      wassertl (0, "Can't determine element size in genArrayInit.");
    }

  wassertl ((elementSize > 0) && (elementSize <= 4), "Illegal element size in genArrayInit.");

  iLoop = IC_ARRAYILIST(ic);
  lastVal = (unsigned)-1;

  /* Feed all the bytes into the run length encoder which will handle
     the actual output.
     This works well for mixed char data, and for random int and long
     data.
  */
  while (iLoop)
    {
      ix = iLoop->count;

      for (i = 0; i < ix; i++)
        {
          for (eIndex = 0; eIndex < elementSize; eIndex++)
            {
              val = (((int)iLoop->literalValue) >> (eIndex * 8)) & 0xff;
              _rleAppend(&rle, val);
            }
        }

      iLoop = iLoop->next;
    }

  _rleFlush(&rle);
  /* Mark the end of the run. */
  emit2(".db 0");

  _restoreRegsAfterCall();

  spillCached ();

  freeAsmop (IC_LEFT(ic), NULL, ic);
}
#endif

#ifdef UNITY
static void
_swap (PAIR_ID one, PAIR_ID two)
{
  if ((one == PAIR_DE && two == PAIR_HL) || (one == PAIR_HL && two == PAIR_DE))
    {
      emit2 ("ex de,hl");
    }
  else
    {
      emit2 ("ld a,%s", _pairs[one].l);
      emit2 ("ld %s,%s", _pairs[one].l, _pairs[two].l);
      emit2 ("ld %s,a", _pairs[two].l);
      emit2 ("ld a,%s", _pairs[one].h);
      emit2 ("ld %s,%s", _pairs[one].h, _pairs[two].h);
      emit2 ("ld %s,a", _pairs[two].h);
    }
}
#endif

static int
setupForMemcpy (const iCode *ic, int nparams, operand **pparams)
{
  PAIR_ID ids[NUM_PAIRS][NUM_PAIRS];
  PAIR_ID dest[3] = {
    PAIR_DE, PAIR_HL, PAIR_BC
  };

  int i;
#ifdef UNITY
  int nunity = 0;
#endif

  bool skip[3] = {FALSE, FALSE, FALSE};
  short dstregs[4];
  short srcregs[4];
  size_t regparamsize = 0;

  memset (ids, PAIR_INVALID, sizeof (ids));

  /* Sanity checks */
  wassertl (nparams == 3, "Built-in memcpy() must have three parameters");

  for (i = 0; i < nparams; i++)
    {
      aopOp (pparams[i], ic, FALSE, FALSE);	// Todo: Free these.
      ids[dest[i]][getPairId (AOP (pparams[i]))] = TRUE;
    }

  wassertl (AOP_TYPE (pparams[2]) == AOP_LIT, "Last parameter to builtin memcpy() must be literal.");

  /* Check for zero length copy. */
  if (!((unsigned int) ulFromVal (AOP (pparams[2])->aopu.aop_lit)))
    return (0);

#ifndef UNITY
  if(AOP_TYPE (pparams[0]) == AOP_REG)
  {
    srcregs[regparamsize] = AOP (pparams[0])->aopu.aop_reg[0]->rIdx;
    dstregs[regparamsize++] = E_IDX;
    srcregs[regparamsize] = AOP (pparams[0])->aopu.aop_reg[1]->rIdx;
    dstregs[regparamsize++] = D_IDX;
    skip[0] = TRUE;
  }
  if(AOP_TYPE (pparams[1]) == AOP_REG)
  {
    srcregs[regparamsize] = AOP (pparams[1])->aopu.aop_reg[0]->rIdx;
    dstregs[regparamsize++] = L_IDX;
    srcregs[regparamsize] = AOP (pparams[1])->aopu.aop_reg[1]->rIdx;
    dstregs[regparamsize++] = H_IDX;
    skip[1] = TRUE;
  }

  if(regparamsize)
    regMove (dstregs, srcregs, regparamsize);

  for (i = 0; i < 3; i++)
    {
      if (!skip[i])
        fetchPair (dest[i], AOP (pparams[i]));
    }

  return (1);
#else 
  /* Count the number of unity or iTemp assigns. */
  for (i = 0; i < 3; i++)
    {
      if (ids[dest[i]][dest[i]] == TRUE || ids[dest[i]][PAIR_INVALID] == TRUE)
        {
          nunity++;
        }
    }

  /* The last parameter is a literal. */
  wassert (nunity);

  if (nunity == 3)
    {
      /* Any order, fall through. */
    }
  else if (nunity == 2)
    {
      /* Two are OK.  Assign the other one. */
      for (i = 0; i < 3; i++)
        {
          for (j = 0; j < NUM_PAIRS; j++)
            {
              if (ids[dest[i]][j] == TRUE)
                {
                  /* Found it.  See if it's the right one. */
                  if (j == PAIR_INVALID || j == dest[i])
                    {
                      /* Keep looking. */
                    }
                  else
                    {
                      fetchPair(dest[i], AOP (pparams[i]));
                      goto done;
                    }
                }
            }
        }
    }
  else if (nunity == 1)
    {
      int k = 0;
      PAIR_ID dest_pairs[2];
      PAIR_ID src_pairs[2];
      int i_pairs[2];
      /* One is OK. Find the other two. */
      for (i = 0; i < 3; i++)
        {
          for (j = 0; j < NUM_PAIRS; j++)
            {
              if (ids[dest[i]][j] == TRUE)
                {
                  if (j == PAIR_INVALID || j == dest[i])
                    {
                      /* This one is OK. */
                    }
                  else
                    {
                      /* Found one. */
                      if(ids[j][dest[i]] == TRUE)
                        {
                          /* Just swap. */
                           _swap (j, dest[i]);
                           goto done;
                        }
                      else
                        {
                          assert (k < 2);
                          dest_pairs[k] = dest[i];
                          src_pairs[k] = j;
                          i_pairs[k] = i;
                          k++;
                          continue;
                        }
                    }
                }
            }
        }
        if(dest_pairs[0] != src_pairs[1])
          {
            fetchPair (dest_pairs[0], AOP (pparams[i_pairs[0]]));
            fetchPair (dest_pairs[1], AOP (pparams[i_pairs[1]]));
          }
        else
          {
            fetchPair (dest_pairs[1], AOP (pparams[i_pairs[1]]));
            fetchPair (dest_pairs[0], AOP (pparams[i_pairs[0]]));
          }
    }

 done:
  /* Finally pull out all of the iTemps */
  for (i = 0; i < 3; i++)
    {
      if (ids[dest[i]][PAIR_INVALID] == 1)
        {
          fetchPair (dest[i], AOP (pparams[i]));
        }
    }

  return (1);
#endif
}

static void
genBuiltInMemcpy (const iCode *ic, int nParams, operand **pparams)
{
  operand *from, *to, *count;

  wassertl (nParams == 3, "Built-in memcpy() must have three parameters");
  count = pparams[2];
  from = pparams[1];
  to = pparams[0];

  _saveRegsForCall (ic, 0, TRUE);

  if (setupForMemcpy (ic, nParams, pparams))
    {
      emit2 ("ldir");
      regalloc_dry_run_cost += 2;
    }

  freeAsmop (count, NULL, ic->next->next);
  freeAsmop (to, NULL, ic->next);
  freeAsmop (from, NULL, ic);

  spillPair (PAIR_HL);

  _restoreRegsAfterCall ();

  /* No need to assign result - would have used ordinary memcpy() call instead. */
}

static void
genBuiltInMemset (const iCode *ic, int nParams, operand **pparams)
{
  operand *dst, *c, *n;
  bool direct_c;

  wassertl (nParams == 3, "Built-in memset() must have three parameters");

  dst = pparams[0];
  c = pparams[1];
  n = pparams[2];

  _saveRegsForCall (ic, 0, TRUE);

  aopOp (c, ic, FALSE, FALSE);
  aopOp (dst, ic, FALSE, FALSE);
  aopOp (n, ic, FALSE, FALSE);

  wassertl (AOP_TYPE (n) == AOP_LIT, "Last parameter to builtin memset() must be literal.");
  if (!(ulFromVal (AOP (n)->aopu.aop_lit)))
    goto done;

  direct_c = (AOP_TYPE (c) == AOP_LIT || AOP_TYPE (c) == AOP_REG && AOP (c)->aopu.aop_reg[1]->rIdx != H_IDX && AOP (c)->aopu.aop_reg[1]->rIdx != L_IDX);

  if (!direct_c)
    cheapMove(ASMOP_A, 0, AOP (c), 0);
  fetchPair (PAIR_HL, AOP (dst));
  if (!regalloc_dry_run)
    emit2 ( "ld (hl), %s", aopGet(direct_c ? AOP (c) : ASMOP_A, 0, FALSE));
  regalloc_dry_run_cost += (direct_c && AOP_TYPE (c) == AOP_LIT) ? 2 : 1;
  if (ulFromVal (AOP (n)->aopu.aop_lit) <= 1)
    goto done;

  emit2 ("ld e, l");
  emit2 ("ld d, h");
  emit2 ("inc de");
  regalloc_dry_run_cost += 3;
  emit2 ("ld bc, #%d", ulFromVal (AOP (n)->aopu.aop_lit) - 1);
  emit2 ("ldir");
  regalloc_dry_run_cost += 5;

done:
  spillPair (PAIR_HL);

  freeAsmop (n, NULL, ic->next->next);
  freeAsmop (c, NULL, ic->next);
  freeAsmop (dst, NULL, ic);

  _restoreRegsAfterCall ();

  /* No need to assign result - would have used ordinary memcpy() call instead. */
}

/*-----------------------------------------------------------------*/
/* genBuiltIn - calls the appropriate function to generate code    */
/* for a built in function                                         */
/*-----------------------------------------------------------------*/
static void
genBuiltIn (iCode *ic)
{
    operand *bi_parms[MAX_BUILTIN_ARGS];
    int nbi_parms;
    iCode *bi_iCode;
    symbol *bif;

    /* get all the arguments for a built in function */
    bi_iCode = getBuiltinParms(ic, &nbi_parms, bi_parms);

    /* which function is it */
    bif = OP_SYMBOL(IC_LEFT(bi_iCode));

    if (!strcmp(bif->name, "__builtin_memcpy"))
      {
        genBuiltInMemcpy(bi_iCode, nbi_parms, bi_parms);
      }
    else if (!strcmp(bif->name, "__builtin_memset"))
      {
        genBuiltInMemset(bi_iCode, nbi_parms, bi_parms);
      }
    else
      {
        wassertl (0, "Unknown builtin function encountered");
      }
}

/*-------------------------------------------------------------------------------------*/
/* genZ80Code - generate code for Z80 based controllers for a single iCode instruction */
/*-------------------------------------------------------------------------------------*/
static void
genZ80iCode (iCode *ic)
{
  _G.current_iCode = ic;

  /* if the result is marked as
     spilt and rematerializable or code for
     this has already been generated then
     do nothing */
  if (resultRemat (ic) || ic->generated)
    return;

  /* depending on the operation */
  switch (ic->op)
    {
    case '!':
      emitDebug ("; genNot");
      genNot (ic);
      break;

    case '~':
      emitDebug ("; genCpl");
      genCpl (ic);
      break;

    case UNARYMINUS:
      emitDebug ("; genUminus");
      genUminus (ic);
      break;

    case IPUSH:
      emitDebug ("; genIpush");
      genIpush (ic);
      break;

    case IPOP:
      /* IPOP happens only when trying to restore a
         spilt live range, if there is an ifx statement
         following this pop then the if statement might
         be using some of the registers being popped which
         would destroy the contents of the register so
         we need to check for this condition and handle it */
      if (ic->next &&
          ic->next->op == IFX &&
          regsInCommon (IC_LEFT (ic), IC_COND (ic->next)))
        {
          emitDebug ("; genIfx");
          genIfx (ic->next, ic);
        }
      else
        {
          emitDebug ("; genIpop");
          genIpop (ic);
        }
      break;

    case CALL:
      emitDebug ("; genCall");
      genCall (ic);
      break;

    case PCALL:
      emitDebug ("; genPcall");
      genPcall (ic);
      break;

    case FUNCTION:
      emitDebug ("; genFunction");
      genFunction (ic);
      break;

    case ENDFUNCTION:
      emitDebug ("; genEndFunction");
      genEndFunction (ic);
      break;

    case RETURN:
      emitDebug ("; genRet");
      genRet (ic);
      break;

    case LABEL:
      emitDebug ("; genLabel");
      genLabel (ic);
      break;

    case GOTO:
      emitDebug ("; genGoto");
      genGoto (ic);
      break;

    case '+':
      emitDebug ("; genPlus");
      genPlus (ic);
      break;

    case '-':
      emitDebug ("; genMinus");
      genMinus (ic);
      break;

    case '*':
      emitDebug ("; genMult");
      genMult (ic);
      break;

    case '/':
      emitDebug ("; genDiv");
      genDiv (ic);
      break;

    case '%':
      emitDebug ("; genMod");
      genMod (ic);
      break;

    case '>':
      emitDebug ("; genCmpGt");
      genCmpGt (ic, ifxForOp (IC_RESULT (ic), ic));
      break;

    case '<':
      emitDebug ("; genCmpLt");
      genCmpLt (ic, ifxForOp (IC_RESULT (ic), ic));
      break;

    case LE_OP:
    case GE_OP:
    case NE_OP:

      /* note these two are xlated by algebraic equivalence
         during parsing SDCC.y */
      werror (E_INTERNAL_ERROR, __FILE__, __LINE__,
              "got '>=' or '<=' shouldn't have come here");
      break;

    case EQ_OP:
      emitDebug ("; genCmpEq");
      genCmpEq (ic, ifxForOp (IC_RESULT (ic), ic));
      break;

    case AND_OP:
      emitDebug ("; genAndOp");
      genAndOp (ic);
      break;

    case OR_OP:
      emitDebug ("; genOrOp");
      genOrOp (ic);
      break;

    case '^':
      emitDebug ("; genXor");
      genXor (ic, ifxForOp (IC_RESULT (ic), ic));
      break;

    case '|':
      emitDebug ("; genOr");
      genOr (ic, ifxForOp (IC_RESULT (ic), ic));
      break;

    case BITWISEAND:
      emitDebug ("; genAnd");
      genAnd (ic, ifxForOp (IC_RESULT (ic), ic));
      break;

    case INLINEASM:
      emitDebug ("; genInline");
      genInline (ic);
      break;

    case RRC:
      emitDebug ("; genRRC");
      genRRC (ic);
      break;

    case RLC:
      emitDebug ("; genRLC");
      genRLC (ic);
      break;

    case GETHBIT:
      emitDebug ("; genGetHbit");
      genGetHbit (ic);
      break;

    case GETABIT:
      emitDebug ("; genGetAbit");
      genGetAbit (ic);
      break;

    case LEFT_OP:
      emitDebug ("; genLeftShift");
      genLeftShift (ic);
      break;

    case RIGHT_OP:
      emitDebug ("; genRightShift");
      genRightShift (ic);
      break;

    case GET_VALUE_AT_ADDRESS:
      emitDebug ("; genPointerGet");
      genPointerGet (ic);
      break;

    case '=':

      if (POINTER_SET (ic))
        {
          emitDebug ("; genAssign (pointer)");
          genPointerSet (ic);
        }
      else
        {
          emitDebug ("; genAssign");
          genAssign (ic);
        }
      break;

    case IFX:
      emitDebug ("; genIfx");
      genIfx (ic, NULL);
      break;

    case ADDRESS_OF:
      emitDebug ("; genAddrOf");
      genAddrOf (ic);
      break;

    case JUMPTABLE:
      emitDebug ("; genJumpTab");
      genJumpTab (ic);
      break;

    case CAST:
      emitDebug ("; genCast");
      genCast (ic);
      break;

    case RECEIVE:
      emitDebug ("; genReceive");
      genReceive (ic);
      break;

    case SEND:
      if (ic->builtinSEND)
        {
          emitDebug ("; genBuiltIn");
          genBuiltIn(ic);
        }
      else if(!regalloc_dry_run)
        {
          emitDebug ("; addSet");
          addSet (&_G.sendSet, ic);
        }
      break;

#if 0
    case ARRAYINIT:
      emitDebug ("; genArrayInit");
      genArrayInit(ic);
      break;
#endif

    case DUMMY_READ_VOLATILE:
      emitDebug ("; genDummyRead");
      genDummyRead (ic);
      break;

    case CRITICAL:
      emitDebug ("; genCritical");
      genCritical (ic);
      break;

    case ENDCRITICAL:
      emitDebug ("; genEndCritical");
      genEndCritical (ic);
      break;

    default:
      ;
    }
}

unsigned char
dryZ80iCode (iCode *ic)
{
  regalloc_dry_run = TRUE;
  regalloc_dry_run_cost = 0;

  /* Hack */
  if (IS_GB)
    {
      _fReturn = _gbz80_return;
      _fTmp = _gbz80_return;
    }
  else
    {
      _fReturn = _z80_return;
      _fTmp = _z80_return;
    }
    
  _G.lines.head = _G.lines.current = NULL;
  
  genZ80iCode(ic);
  
  freeTrace(&_G.lines.trace);
  freeTrace(&_G.trace.aops);

  {
    int pairId;
    for(pairId = 0; pairId < NUM_PAIRS; pairId++)
      spillPair (pairId);
  }

  return(regalloc_dry_run_cost);
}

#ifdef DEBUG_DRY_COST
static void
dryZ80Code (iCode * lic)
{
  iCode *ic;

  for (ic = lic; ic; ic = ic->next)
    if(ic->op != FUNCTION && ic->op != ENDFUNCTION && ic->op != LABEL && ic->op != GOTO && ic->op != INLINEASM)
      printf("; iCode %d total cost: %d\n", ic->key, (int)(dryZ80iCode (ic)));
}
#endif

/*-------------------------------------------------------------------------------------*/
/* genZ80Code - generate code for Z80 based controllers for a block of intructions     */
/*-------------------------------------------------------------------------------------*/
void
genZ80Code (iCode *lic)
{
#ifdef DEBUG_DRY_COST
  dryZ80Code(lic);
#endif

  iCode *ic;
  int cln = 0;
  regalloc_dry_run = FALSE;

  /* Hack */
  if (IS_GB)
    {
      _fReturn = _gbz80_return;
      _fTmp = _gbz80_return;
    }
  else
    {
      _fReturn = _z80_return;
      _fTmp = _z80_return;
    }

  _G.lines.head = _G.lines.current = NULL;

  /* if debug information required */
  if (options.debug && currFunc)
    {
      debugFile->writeFunction (currFunc, lic);
    }

  for (ic = lic; ic; ic = ic->next)
    ic->generated = FALSE;

  /* Generate Code for all instructions */
  for (ic = lic; ic; ic = ic->next)
    {
      if (ic->lineno && cln != ic->lineno)
        {
          if (options.debug)
           debugFile->writeCLine (ic);
          if (!options.noCcodeInAsm)
            emit2 (";%s:%d: %s", ic->filename, ic->lineno, printCLine(ic->filename, ic->lineno));
          cln = ic->lineno;
        }
      if (options.iCodeInAsm)
        {
          const char *iLine = printILine(ic);
          emit2 (";ic:%d: %s", ic->key, iLine);
          dbuf_free(iLine);
        }
      regalloc_dry_run_cost = 0;
      genZ80iCode (ic);
      //emitDebug("; iCode %d total cost: %d", ic->key, (int)(regalloc_dry_run_cost));
    }


  /* now we are ready to call the
     peep hole optimizer */
  if (!options.nopeep)
    peepHole (&_G.lines.head);

  /* This is unfortunate */
  /* now do the actual printing */
  {
    struct dbuf_s *buf = codeOutBuf;
    if (isInHome () && codeOutBuf == &code->oBuf)
      codeOutBuf = &home->oBuf;
    printLine (_G.lines.head, codeOutBuf);
    if (_G.flushStatics)
      {
        flushStatics ();
        _G.flushStatics = 0;
      }
    codeOutBuf = buf;
  }

  {
    int pairId;
    for(pairId = 0; pairId < NUM_PAIRS; pairId++)
      spillPair (pairId);
  }

  freeTrace(&_G.lines.trace);
  freeTrace(&_G.trace.aops);
}

/*
  Attic
static int
_isPairUsed (iCode * ic, PAIR_ID pairId)
{
  int ret = 0;
  switch (pairId)
    {
    case PAIR_DE:
      if (bitVectBitValue (ic->rMask, D_IDX))
        ret++;
      if (bitVectBitValue (ic->rMask, E_IDX))
        ret++;
      break;
    default:
      wassert (0);
    }
  return ret;
}
*/

