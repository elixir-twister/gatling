defmodule Mix.Tasks.Gatling.Deploy do
  use Mix.Task

  import Gatling.Bash, only: [bash: 3, log: 1]

  @moduledoc """
  - Create a release of git HEAD using Exrm
  - Create a init script for the app so it will reboot on a server reboot
  - Configure Nginx go serve it
  - Start the app
  """

  @shortdoc "Create an exrm release of the given project and deploy it"

  def run([project_name]) do
    deploy(project_name)
  end

  defp deploy(project) do
    deploy_path = Gatling.Utilities.deploy_dir(project)
    build_path  = Gatling.Utilities.build_path(project)
    port        = Gatling.Utilities.available_port

    mix_deps_get(build_path)
    mix_compile(build_path)
    make_deploy_dir(deploy_path)
    mix_release(build_path)
    copy_release_to_deploy(build_path, deploy_path)
    expand_release(project, deploy_path)
    install_nginx_site(build_path, port)
    install_init_script(project, port)
    start_service(project, port)
  end

  def mix_deps_get(build_path) do
    bash("mix", ["deps.get"], cd: build_path)
  end

  def mix_compile(build_path) do
    bash("mix", ~w[compile --force], cd: build_path)
    bash("mix", ~w[phoenix.digest -o public/static], cd: build_path)
  end

  def mix_release(build_path) do
    bash("mix", ~w[release --no-confirm-missing], cd: build_path)
  end

  def make_deploy_dir(deploy_path) do
    File.mkdir_p(deploy_path)
  end

  def copy_release_to_deploy(build_path, deploy_path) do
    project      = Path.basename(build_path)
    deploy_path  = Path.join(deploy_path, "#{project}.tar.gz")
    version      = Gatling.Utilities.version(build_path)

    [build_path, "rel", project, "releases", version, "#{project}.tar.gz"]
    |> Path.join()
    |> File.cp(deploy_path)

    log("Release copied to #{deploy_path}")
  end

  def expand_release(project, deploy_path) do
    bash("tar", ["-xf", "#{project}.tar.gz"], cd: deploy_path, message: "Extracting #{project}")
  end

  def install_init_script(project_name, port) do
    file      = Gatling.Utilities.script_template(project_name: project_name, port: port)
    init_path = Path.join([Gatling.Utilities.etc_path, project_name])
    File.write(init_path, file)
    File.chmod(init_path, 0100)
    bash("update-rc.d", ~w[#{ project_name } defaults], [])
    log("Added service #{project_name} in #{Gatling.Utilities.etc_path}")
  end

  def start_service(project, port) do
    bash("service", ~w[#{project} start], env: [{"PORT", to_string(port)}])
    log("Started service #{project}")
  end

  def install_nginx_site(build_path, port) do
    project_name = build_path |> Path.basename()
    file         = Gatling.Utilities.nginx_template( domains: domains(build_path), port: port,)
    available    = Path.join([Gatling.Utilities.nginx_path, "sites-available", project_name])
    enabled      = Path.join([Gatling.Utilities.nginx_path, "sites-enabled", project_name])
    File.write(available, file)
    File.ln_s(available, enabled)
    bash("nginx", ~w[-s reload], message: "Configuring nginx")
  end

  def domains(build_path) do
    Path.join(build_path, "domains")
    |> File.read!()
    |> String.split(~r/,?\s/, trim: true)
    |> Enum.join(" ")
  end

end
