
"""LBNL Data Repository custom package.

This package contains customizations for the LBNL Data Repository InvenioRDM instance,
including custom static pages for FAQ, News, and Terms.
"""

from .views import create_blueprint

__version__ = '0.1.0'

__all__ = ('create_blueprint','__version__')
