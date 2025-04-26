#!/usr/bin/env python
"""LBNL Data Repository InvenioRDM extension."""

from setuptools import find_packages, setup

setup(
    name='lbnl-data-repository',
    version='0.1.0',
    description="LBNL Data Repository customizations for InvenioRDM",
    packages=find_packages(),
    zip_safe=False,
    include_package_data=True,
    platforms='any',
    entry_points={
        'invenio_base.blueprints': [
            'lbnl_pages = lbnl_data_repository.views:create_blueprint',
        ],
        'invenio_assets.webpack': [
            'lbnl_data_repository_theme = lbnl_data_repository.webpack:theme',
        ],
    },
    install_requires=[
        'invenio-app-rdm>=12.0.0',
    ],
    classifiers=[
        'Environment :: Web Environment',
        'Intended Audience :: Developers',
        'Programming Language :: Python :: 3',
        'Topic :: Internet :: WWW/HTTP :: Dynamic Content',
    ],
)
