library(shiny)
library(shinyWidgets)
library(ctmm)
library(sf)
library(glue)
library(dplyr)
library(purrr)
library(leaflet)
library(zip)
library(shinycssloaders)


shinyModuleUserInterface <- function(id, label) {
  ns <- NS(id) ## all IDs of UI functions need to be wrapped in ns()
  tagList(
    titlePanel("Occurrence distribution"),
    fluidRow(
      column(6,
             sliderInput(
               ns("isopleth_levels"),
               "Isopleth level:",
               min = 0.01, max = .99, value = .95
             ),
      ), 
      column(6, 
             sliderInput(ns("opacity"), "Opacity", min = 0, max = 1, value = 0.5), 
             actionButton(ns("clear"), label = "Remove all animals from map")
      ) 
    ),
    hr(),
    shinycssloaders::withSpinner(leafletOutput(ns("map"), height = "800"))
  )
}

shinyModule <- function(input, output, session, data){ ## The parameter "data" is reserved for the data object passed on from the previous app
  ns <- session$ns ## all IDs of UI functions need to be wrapped in ns()
  
  occu <- occurrence(data[[2]], data[[1]])
  bbx <- map(occu, ~ st_as_sf(ctmm::SpatialPolygonsDataFrame.UD(.x, level.UD = 0.97)) |> 
               st_transform(4326)) |> 
    map(st_bbox)
  bbx <- do.call(rbind, bbx)
  
  occu.iso <- reactive({
    occu_sf <- map(occu, ~ sf::st_as_sf(ctmm::SpatialPolygonsDataFrame.UD(.x, level.UD = input$isopleth_levels))) |> bind_rows()
    
    # export as geopackage
    occu_sf |> 
      sf::st_write(appArtifactPath("occurrence.gpkg"), append = FALSE)
    occu_sf
  })
  
  
  occu.leaflet <- reactive({
    occu_sf <- occu.iso() %>%  
      st_transform(4326) |> 
      group_split(name)
    names(occu_sf) <- names(occu)
    occu_sf
  })
  
  output$map <- renderLeaflet({
    leaflet() |> 
      addTiles(group = "OSM") |> 
      addTiles('http://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 
               options = providerTileOptions(noWrap = TRUE), group="World Imagery") |> 
      addProviderTiles(providers$Stamen.Toner, group = "Toner") |> 
      addProviderTiles(providers$Stamen.TonerLite, group = "Toner Lite") |> 
      fitBounds(min(bbx[, 1]), min(bbx[, 2]), max(bbx[, 3]), max(bbx[, 4]))
    
  })
  
  cols <- rainbow(length(occu))
  
  observe({
    m <- leafletProxy("map") |> 
      clearShapes() |> 
      clearControls()
    for (i in 1:length(occu.leaflet())) {
      m <- m |> addPolygons(data = occu.leaflet()[[i]],
                            group = names(occu.leaflet())[i], 
                            color = cols[i],
                            fillColor = cols[i],
                            fillOpacity = input$opacity)
    }
    
    
    m |> 
      addLayersControl(
        baseGroups = c("OSM", "Wolrd Imagery", "Toner", "Toner Lite"),
        overlayGroups = names(occu.leaflet()),
        options = layersControlOptions(collapsed = TRUE)
      ) |> 
      addLegend(
        position = "bottomright",
        colors = cols,
        labels  = names(occu))  
    
  })
  observeEvent(input$clear, {
    leafletProxy("map") |> 
      hideGroup(names(occu.leaflet()))
  })
  
  
  # Artefact: tifs
  dir.create(targetDirUDs <- tempdir())
  
  r <- lapply(names(occu), function(x) 
    writeRaster(occu[[x]], file.path(targetDirUDs, paste0(x, ".tif")), overwrite = TRUE))
  
  zip::zip(
    zipfile = appArtifactPath("occurence_uds.zip"),
    files = list.files(targetDirUDs, full.names = TRUE, pattern = "tif$"),
    mode = "cherry-pick"
  )
  
  return(reactive({ 
    c(data[[2]], list(occu), data[[1]])
  })) ## if data are not modified, the unmodified input data must be returned
}
