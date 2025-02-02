open Capnp_rpc_lwt

module Build_status = struct
  include Raw.Reader.BuildStatus

  let pp f = function
    | NotStarted -> Fmt.string f "not started"
    | Failed -> Fmt.pf f "@{<red>failed@}"
    | Passed -> Fmt.pf f "@{<green>passed@}"
    | Pending -> Fmt.pf f "@{<yellow>pending@}"
    | Undefined x -> Fmt.pf f "unknown:%d" x

  let color = function
    | NotStarted -> `None
    | Failed -> `Fg `Red
    | Passed -> `Fg `Green
    | Pending -> `Fg `Yellow
    | Undefined _ -> `None

  let to_yojson = function
    | NotStarted -> `String "not started"
    | Failed -> `String "failed"
    | Passed -> `String "passed"
    | Pending -> `String "pending"
    | Undefined _ -> `String "unknown"
end

module State = struct
  type t =
    | Aborted
    | Failed of string
    | NotStarted
    | Active
    | Passed
    | Undefined of int

  let pp f = function
    | NotStarted -> Fmt.string f "not started"
    | Aborted -> Fmt.string f "aborted"
    | Failed m -> Fmt.pf f "failed: %s" m
    | Passed -> Fmt.string f "passed"
    | Active -> Fmt.string f "active"
    | Undefined x -> Fmt.pf f "unknown:%d" x

  let from_build_status = function
    | Build_status.Failed -> Failed ""
    | NotStarted -> NotStarted
    | Pending -> Active
    | Passed -> Passed
    | Undefined x -> Undefined x
end

module Package = struct
  type t = Raw.Client.Package.t Capability.t
  type package_version = { version : OpamPackage.Version.t }
  type package_info = Raw.Reader.PackageInfo.t

  let package_info_to_yojson pi =
    `Assoc [ ("package", `String (Raw.Reader.PackageInfo.name_get pi)) ]

  type package_info_list = package_info list [@@deriving to_yojson]

  type package_status = {
    version : OpamPackage.Version.t;
    status : Build_status.t;
  }

  let package_status_to_yojson { version; status } =
    let version = `String (version |> OpamPackage.Version.to_string) in
    let status = Build_status.to_yojson status in
    `Assoc [ ("version", version); ("status", status) ]

  type package_status_list = package_status list [@@deriving to_yojson]

  type step = { typ : string; job_id : string option; status : Build_status.t }
  [@@deriving to_yojson]

  type package_steps = {
    version : string;
    status : Build_status.t;
    steps : step list;
  }
  [@@deriving to_yojson]

  type package_steps_list = package_steps list [@@deriving to_yojson]

  let versions t =
    let open Raw.Client.Package.Versions in
    let request = Capability.Request.create_no_args () in
    Capability.call_for_value t method_id request
    |> Lwt_result.map (fun x ->
           x
           |> Results.versions_get_list
           |> List.map (fun x ->
                  {
                    version =
                      Raw.Reader.PackageBuildStatus.version_get x
                      |> OpamPackage.Version.of_string;
                    status = Raw.Reader.PackageBuildStatus.status_get x;
                  }))

  let steps t =
    let open Raw.Client.Package.Steps in
    let request, _ = Capability.Request.create Params.init_pointer in
    Capability.call_for_value t method_id request
    |> Lwt_result.map @@ fun package_steps ->
       let open Raw.Reader.PackageSteps in
       Results.steps_get_list package_steps
       |> List.map @@ fun package_slot ->
          let package_version = version_get package_slot in
          let status = status_get package_slot in
          let steps =
            steps_get_list package_slot
            |> List.map (fun x ->
                   let open Raw.Reader.StepInfo in
                   let status = status_get x in
                   let typ = type_get x in
                   let job_id_t = job_id_get x in
                   let job_id =
                     match JobId.get job_id_t with
                     | JobId.None | JobId.Undefined _ -> None
                     | JobId.Id s -> Some s
                   in
                   { typ; job_id; status })
          in
          (package_version, status, steps)

  let by_pipeline t pipeline_id =
    let open Raw.Client.Package.ByPipeline in
    let request, params = Capability.Request.create Params.init_pointer in
    Params.pipeline_id_set params pipeline_id;
    Capability.call_for_value t method_id request
    |> Lwt_result.map (fun x ->
           x
           |> Results.versions_get_list
           |> List.map (fun x ->
                  {
                    version =
                      Raw.Reader.PackageBuildStatus.version_get x
                      |> OpamPackage.Version.of_string;
                    status = Raw.Reader.PackageBuildStatus.status_get x;
                  }))
end

module Pipeline = struct
  type t = Raw.Client.Pipeline.t Capability.t
  type health = Raw.Reader.PipelineHealth.t

  let health_to_yojson h =
    let open Raw.Reader.PipelineHealth in
    let epoch_html = epoch_html_get h in
    let epoch_linked = epoch_linked_get h in
    let voodoo_do = voodoo_do_commit_get h in
    let voodoo_prep = voodoo_prep_commit_get h in
    let voodoo_gen = voodoo_gen_commit_get h in
    let voodoo_branch = voodoo_branch_get h in
    let voodoo_repo = voodoo_repo_get h in
    let odoc_commit = odoc_commit_get h in
    let failed_packages = failing_packages_get h |> Int64.to_int in
    let running_packages = running_packages_get h |> Int64.to_int in
    let passed_packages = passing_packages_get h |> Int64.to_int in
    `Assoc
      [
        ("epoch_html", `String epoch_html);
        ("epoch_linked", `String epoch_linked);
        ("voodoo_do", `String voodoo_do);
        ("voodoo_prep", `String voodoo_prep);
        ("voodoo_gen", `String voodoo_gen);
        ("odoc", `String odoc_commit);
        ("voodoo_repo", `String voodoo_repo);
        ("voodoo_branch", `String voodoo_branch);
        ("failed_packages", `Int failed_packages);
        ("running_packages", `Int running_packages);
        ("passed_packages", `Int passed_packages);
      ]

  let package t name =
    let open Raw.Client.Pipeline.Package in
    let request, params = Capability.Request.create Params.init_pointer in
    Params.package_name_set params name;
    Capability.call_for_caps t method_id request Results.package_get_pipelined

  let packages t =
    let open Raw.Client.Pipeline.Packages in
    let request = Capability.Request.create_no_args () in
    Capability.call_for_value t method_id request
    |> Lwt_result.map Results.packages_get_list

  let health t pipeline_id =
    let open Raw.Client.Pipeline.Health in
    let request, params = Capability.Request.create Params.init_pointer in
    Params.pipeline_id_set params pipeline_id;
    Capability.call_for_value t method_id request
    |> Lwt_result.map Results.health_get

  let diff t pipeline_id_one pipeline_id_two =
    let open Raw.Client.Pipeline.Diff in
    let request, params = Capability.Request.create Params.init_pointer in
    Params.pipeline_id_one_set params pipeline_id_one;
    Params.pipeline_id_two_set params pipeline_id_two;
    Capability.call_for_value t method_id request
    |> Lwt_result.map Results.failing_packages_get_list

  let pipeline_ids t =
    let open Raw.Client.Pipeline.PipelineIds in
    let request, _params = Capability.Request.create Params.init_pointer in
    Capability.call_for_value t method_id request
    |> Lwt_result.map (fun x ->
           (Results.latest_get x, Results.latest_but_one_get x))
end
