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
%{ if public_domain_name != "" ~}
${public_domain_name}:53 {
    reload
    loop
    forward . ${dns_forward_target}
}
%{ endif ~}
.:53 {
    reload
    loop
    forward . 1.1.1.1 8.8.8.8
}
