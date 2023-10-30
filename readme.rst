PowerShell scripts
========================================================================================================================

Collection of generic and multi-purpose *PowerShell* scripts intended for support, CI/CD and general
automation. They can be used as they are or used as an example for more complex scripts. It is possible that these
scripts run on *PowerShell v5*, although they are developed for use with *PowerShell v7*.

The `modules` folder contains:

- *linters.psm1*, functionality related to linting tools such as *cppcheck*, *clang-tidy* or *doc8*.
- *documentation.psm1*, functionality related to documentation tools such as *doxygen* or *sphinx*.
- *tests.psm1*, functionality related to test and coverage tools such as *fastcov*, *cmocka* or *junit2html*.
- *devcontainers.psm1*, functionality related to *docker*, *docker-compose*, *vscode* and *devcontainers*.
- *commons.psm1*, functionality common to all modules or that does not fit anywhere else.

Working with this repository
------------------------------------------------------------------------------------------------------------------------

This project requires PowerShell, Docker, Visual Studio Code with Remote Containers extension and the DevContainers CLI.

Pull the Docker image with ``docker pull dmg00345/powershell_scripts`` or alternatively built it from scratch like
``.\manage.ps1 build``. Afterwards do ``.\manage.ps1 run`` to build the development container and volume if not already
built and open Visual Studio Code.

The paths to the *Github* environment variables file, SSH authentication key and SSH signing key need to be specified in
``.devcontainer/compose.yaml`` and ``manage.ps1`` files, see initialization script in ``manage.ps1 run`` for details.
