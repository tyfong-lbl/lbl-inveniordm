
"""LBNL Data Repository custom package.

This package contains customizations for the LBNL Data Repository InvenioRDM instance,
including custom static pages for FAQ, News, and Terms.
"""

from .views import create_blueprint

__all__ = ('create_blueprint',)
