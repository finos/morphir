package morphir.sdk

@org.springframework.web.bind.annotation.RestController
abstract class SpringBootStatefulAppAdapter [K, C, S, E] (statefulApp: StatefulApp [K, C, S, E]) {
  @org.springframework.web.bind.annotation.RequestMapping(value = Array("/logic"), method = Array(org.springframework.web.bind.annotation.RequestMethod.GET))
    def entryPoint(key: K, command: C)  {
      process(key, read(key), command)
  }

  def read(key: K): Option[S]
  def process(key: K, state: Option[S], command: C){
    statefulApp.businessLogic(key, state, command)
  }
  def serialize(key: K, state: S, event: E)
}
