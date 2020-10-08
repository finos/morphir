package company.operations


abstract class SpringBootStatefulAppAdapter [K, C, S, E] (statefulApp: morphir.sdk.StatefulApp [K, C, S, E]) {
  @org.springframework.web.bind.annotation.PostMapping(value= Array("/deal"), consumes = Array(org.springframework.http.MediaType.APPLICATION_JSON_VALUE), produces = Array("application/json"))
    def entryPoint(@org.springframework.web.bind.annotation.RequestBody command: C)  {
      var key = deserialize(command)
      return process(key, read(key), command)
  }

  def process(key: K, state: Option[S], command: C){
    statefulApp.businessLogic(key, state, command)
  }

}
