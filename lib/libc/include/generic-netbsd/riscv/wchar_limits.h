/* $NetBSD: wchar_limits.h,v 1.1 2014/09/19 17:36:26 matt Exp $ */

// zig patch: https://github.com/llvm/llvm-project/issues/199678
#ifndef _RISCV_WCHAR_LIMITS_H_
#define _RISCV_WCHAR_LIMITS_H_

#define	WCHAR_MIN	(-0x7fffffff-1)			/* wchar_t	  */
#define	WCHAR_MAX	0x7fffffff			/* wchar_t	  */

#define	WINT_MIN	(-0x7fffffff-1)			/* wint_t	  */
#define	WINT_MAX	0x7fffffff			/* wint_t	  */

#endif /* !_RISCV_WCHAR_LIMITS_H_ */
