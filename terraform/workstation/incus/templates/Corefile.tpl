${context}:53 {
    hosts {
%{ for entry in host_entries ~}
        ${entry}
%{ endfor ~}
        fallthrough
    }

    reload
    loop
    forward . ${dns_forward_target}
}
%{ for domain in extra_domain_names ~}
${domain}:53 {
    reload
    loop
    forward . ${dns_forward_target}
}
%{ endfor ~}
.:53 {
    reload
    loop
    forward . 1.1.1.1 8.8.8.8
}
