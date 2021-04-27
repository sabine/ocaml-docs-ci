val cap : 'a Capnp_rpc_lwt.Sturdy_ref.t

val ssh_secrets : Obuilder_spec.Secret.t list

val ssh_secrets_values : (string * string) list

val ssh_host : string

val ssh_user : string

val ssh_priv_key_file : Fpath.t

val ssh_port : int

val docs_public_endpoint : string
(** The public URL to access the docs files *)

val storage_folder : string
(** Path of the global storage folder *)

val odoc : string
(** Odoc version pin to use. *)

val odoc_bin : string
(** Local odoc binary for the final link step. Must be 
the same version as odoc *)

val pool : string
(** The ocluster pool to use *)

val ocluster_connection : Current_ocluster.Connection.t
(** Connection to the cluster *)

val jobs : int
(** Number of jobs that can be spawned for the steps that are locally executed. *)