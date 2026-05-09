// kin-generated — per-service export policy (services.<n>.exportTo)
permit(principal, action, resource == Service::"attest")
  when { principal in Fleet::"bir7vyhu7hjc6ybptojyjerh2nepv6oe" };

permit(principal, action, resource == Service::"builders")
  when { principal in Fleet::"bir7vyhu7hjc6ybptojyjerh2nepv6oe" };

permit(principal, action, resource == Service::"identity")
  when { principal in Fleet::"bir7vyhu7hjc6ybptojyjerh2nepv6oe" };

permit(principal, action, resource == Service::"ietsd")
  when { principal in Fleet::"bir7vyhu7hjc6ybptojyjerh2nepv6oe" };

permit(principal, action, resource == Service::"llm-adapter")
  when { principal in Fleet::"bir7vyhu7hjc6ybptojyjerh2nepv6oe" };

permit(principal, action, resource == Service::"mesh")
  when { principal in Fleet::"bir7vyhu7hjc6ybptojyjerh2nepv6oe" };

permit(principal, action, resource == Service::"users")
  when { principal in Fleet::"bir7vyhu7hjc6ybptojyjerh2nepv6oe" };
