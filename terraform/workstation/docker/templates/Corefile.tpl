%{ if use_localhost_networking ~}
${context}:${host_answer_port} {
    template IN A {
        match "^.*\.${context}\.$"
        answer "{{ .Name }} 60 IN A 127.0.0.1"
    }
    reload
    loop
}
${context}:53 {
    reload
    loop
    forward . ${dns_forward_target}
}
%{ else ~}
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
%{ endif ~}
.:53 {
    reload
    loop
    forward . 1.1.1.1 8.8.8.8
}
