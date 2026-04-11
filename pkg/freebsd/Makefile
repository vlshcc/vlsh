PORTNAME=	vlsh
DISTVERSIONPREFIX=	v
DISTVERSION=	1.2.0
CATEGORIES=	shells

MAINTAINER=	sarmonsiill@tilde.guru
COMMENT=	Interactive shell written in V
WWW=		https://github.com/vlshcc/vlsh

LICENSE=	MIT
LICENSE_FILE=	${WRKSRC}/LICENSE

BUILD_DEPENDS=	v:lang/v

USE_GITHUB=	yes
GH_ACCOUNT=	vlshcc

do-build:
	cd ${WRKSRC} && v -prod -o ${WRKSRC}/${PORTNAME} .

do-install:
	${INSTALL_PROGRAM} ${WRKSRC}/${PORTNAME} \
		${STAGEDIR}${PREFIX}/bin/${PORTNAME}

PLIST_FILES=	"@shell bin/vlsh"

.include <bsd.port.mk>
