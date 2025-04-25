"""Blueprint definitions for LBNL static pages."""

from flask import Blueprint, render_template


def create_blueprint(app):
    """Create LBNL pages blueprint.
    
    This factory function creates a Flask blueprint for static pages
    including FAQ, News, and Terms. The blueprint is designed to be
    registered with the Invenio application via entry points.
    
    Args:
        app: The Flask application instance
        
    Returns:
        Blueprint: A Flask blueprint with routes for static pages
    """
    blueprint = Blueprint(
        "lbnl_pages",
        __name__,
        template_folder="templates",
        static_folder="static",
        url_prefix="/"
    )

    @blueprint.route("/faq")
    def faq():
        """Render the FAQ page.
        
        Returns:
            str: Rendered HTML for the FAQ page
        """
        return render_template("lbnl_data_repository/faq.html")

    @blueprint.route("/news")
    def news():
        """Render the News page.
        
        Returns:
            str: Rendered HTML for the News page
        """
        return render_template("lbnl_data_repository/news.html")

    @blueprint.route("/terms")
    def terms():
        """Render the Terms page.
        
        Returns:
            str: Rendered HTML for the Terms page
        """
        return render_template("lbnl_data_repository/terms.html")

    return blueprint

