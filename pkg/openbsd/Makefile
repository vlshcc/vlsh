# $OpenBSD$

V =		1.2.0

COMMENT =	interactive shell written in V

DISTNAME =	vlsh-${V}
SITES =		https://github.com/vlshcc/vlsh/archive/
DISTFILES =	v${V}${EXTRACT_SUFX}

CATEGORIES =	shells

HOMEPAGE =	https://github.com/vlshcc/vlsh

MAINTAINER =	David Satime Wallin <sarmonsiill@tilde.guru>

# MIT
PERMIT_PACKAGE =	Yes

WANTLIB += c m pthread

BUILD_DEPENDS =	lang/v

# Matches lang/v (V compiler)
ONLY_FOR_ARCHS = amd64 arm64

do-build:
	cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} ${LOCALBASE}/bin/v -prod -o ${WRKSRC}/vlsh .

do-install:
	${INSTALL_PROGRAM} ${WRKSRC}/vlsh ${PREFIX}/bin/vlsh

.include <bsd.port.mk>
